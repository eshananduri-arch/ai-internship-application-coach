"""Run separately: python -m app.worker. Accepted jobs survive this process."""
import argparse
import logging
import signal
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from uuid import UUID,uuid4
from psycopg.types.json import Jsonb
from .coaching import Coach
from .config import get_settings
from .db import Database
from .documents import extract_text
from .errors import AppError, PipelineError
from .security import Encryption

log=logging.getLogger('firstrole.worker')

class WorkerManager:
    def __init__(self,settings,coach=None):
        self.settings=settings
        self.db=Database(settings.worker_database_url.get_secret_value(),max(4,settings.max_worker_concurrency*2+2),'firstrole-worker')
        self.ops=Database(settings.operator_database_url.get_secret_value(),2,'firstrole-controller')
        self.encryption=Encryption(settings)
        self.coach=coach or Coach(settings)
        self.worker_id=uuid4()
        self.stop=threading.Event()
        self.executor=None; self.capacity=0
        self.active={}; self.last_work=time.monotonic()
        self.last_control=0; self.last_reconcile=0

    def control(self):
        if self.ops.pool is None: return
        with self.ops.transaction() as c:
            settings=c.execute('SELECT * FROM app.worker_settings WHERE singleton FOR UPDATE').fetchone()
            snapshot=c.execute('SELECT app.operations_snapshot() value').fetchone()['value']
            if not settings['auto_manage'] or settings['paused']: return
            desired=2 if snapshot['jobs'].get('queued',0)>=settings['backlog_per_slot'] else 1
            desired=max(settings['min_concurrency'],min(desired,settings['max_concurrency'],self.settings.max_worker_concurrency))
            if settings['throttle_until'] and settings['throttle_until'].timestamp()>time.time(): desired=min(desired,1)
            if desired!=settings['target_concurrency']:
                c.execute('''UPDATE app.worker_settings SET target_concurrency=%s,last_scaled_at=now(),updated_at=now()
                    WHERE singleton AND last_scaled_at<=now()-make_interval(secs=>cooldown_seconds)''',(desired,))

    def tick(self):
        for future in list(self.active):
            if future.done():
                try: future.result()
                except Exception as error: log.error('worker_task_failed type=%s',type(error).__name__)
                del self.active[future]
        now=time.monotonic()
        if now-self.last_control>=5:
            self.control(); self.last_control=now
        with self.db.transaction() as c:
            c.execute('''INSERT INTO app.worker_heartbeats(worker_id) VALUES(%s)
                ON CONFLICT(worker_id) DO UPDATE SET last_seen_at=now(),draining=%s''',(self.worker_id,self.stop.is_set()))
            state=c.execute('SELECT * FROM app.worker_settings WHERE singleton').fetchone()
            if now-self.last_reconcile>=10:
                c.execute('SELECT app.reconcile_jobs()'); self.last_reconcile=now
        target=min(state['target_concurrency'],self.settings.max_worker_concurrency)
        if state['paused'] or (state['throttle_until'] and state['throttle_until'].timestamp()>time.time()): target=0
        if not self.settings.coaching_configured: target=0
        if self.executor and self.capacity!=target:
            self.executor.shutdown(wait=False,cancel_futures=False)
            self.executor=None; self.capacity=0
        if self.stop.is_set(): return
        while len(self.active)<target:
            with self.db.transaction() as c:
                message=c.execute('SELECT * FROM app.read_analysis_queue(1)').fetchone()
                if not message: break
                try: job_id=UUID(str(message['message']['job_id']))
                except (KeyError,ValueError,TypeError):
                    # Payloads are produced by the database trigger; malformed
                    # messages require an operator rather than unsafe deletion.
                    log.error('invalid_queue_payload'); break
                lease=c.execute('SELECT * FROM app.claim_worker_slot(%s,%s)',(self.worker_id,job_id)).fetchone()
                if not lease:
                    c.execute('SELECT app.defer_unclaimed_job(%s)',(job_id,)); break
            if self.executor is None:
                self.capacity=target
                self.executor=ThreadPoolExecutor(max_workers=target,thread_name_prefix='firstrole-job')
            future=self.executor.submit(self.process,job_id,lease['lease_token'])
            self.active[future]=job_id
            self.last_work=time.monotonic()
        if not self.active and self.executor and time.monotonic()-self.last_work>=self.settings.thread_idle_seconds:
            self.executor.shutdown(wait=False); self.executor=None; self.capacity=0

    def process(self,job_id,token):
        heartbeat_stop=threading.Event(); lease_lost=threading.Event()
        def heartbeat():
            while not heartbeat_stop.wait(15):
                try:
                    with self.db.transaction() as c:
                        valid=c.execute('SELECT app.heartbeat_worker_slot(%s,%s) ok',(self.worker_id,token)).fetchone()['ok']
                    if not valid: lease_lost.set(); return
                except Exception:
                    # A failed heartbeat must not permit an unfenced write.
                    log.warning('heartbeat_unavailable')
        thread=threading.Thread(target=heartbeat,name='firstrole-lease',daemon=True)
        thread.start()
        started=time.monotonic()
        try:
            with self.db.transaction() as c:
                job=c.execute('SELECT * FROM app.analysis_jobs WHERE id=%s',(job_id,)).fetchone()
                analysis=c.execute('SELECT * FROM app.analyses WHERE id=%s',(job['analysis_id'],)).fetchone()
                resume=c.execute('SELECT * FROM app.resumes WHERE id=%s',(analysis['resume_id'],)).fetchone()
                c.execute("UPDATE app.analyses SET status='processing',stage='Reading your uploaded resume',updated_at=now() WHERE id=%s",(analysis['id'],))
            if resume['encryption_key_version']!=self.settings.encryption_key_version:
                raise PipelineError('encryption_key_version_unavailable')
            original=self.encryption.decrypt(resume['encrypted_original'])
            text=extract_text(original,resume['file_type'])
            del original
            with self.db.transaction() as c:
                if not c.execute('SELECT app.heartbeat_worker_slot(%s,%s) ok',(self.worker_id,token)).fetchone()['ok']:
                    return
                c.execute("UPDATE app.resumes SET encrypted_text=%s,extraction_status='ready',character_count=%s WHERE id=%s",(self.encryption.encrypt(text.encode()),len(text),resume['id']))
                c.execute("UPDATE app.analyses SET stage='Matching the role and reviewing your letter',updated_at=now() WHERE id=%s",(analysis['id'],))
            result=self.coach.generate(analysis,text,job['attempt_count'])
            del text
            if lease_lost.is_set(): return
            with self.db.transaction() as c:
                usage=result['usage']
                settled=c.execute('SELECT app.settle_job_usage(%s,%s,%s,%s,%s,%s) ok',
                    (self.worker_id,token,'n8n',str(usage.get('model','reported-pipeline'))[:100],usage['input_tokens'],usage['output_tokens'])).fetchone()['ok']
                if not settled: return
                done=c.execute("SELECT app.finish_analysis_job(%s,%s,'succeeded') ok",(self.worker_id,token)).fetchone()['ok']
                if not done: raise RuntimeError('Lease changed during completion')
                c.execute('''UPDATE app.analyses SET status='ready',stage='Ready for your review',final_letter=%s,draft_version=draft_version+1,
                    match_report=%s,deadline_info=%s,critic_review=%s,tool_evidence=%s,approval_allowed=true,failure_code=NULL,updated_at=now() WHERE id=%s''',
                    (result['final_letter'],Jsonb(result['match_report']),Jsonb(result['deadline_info']),Jsonb(result['critic_review']),Jsonb(result['tool_evidence']),analysis['id']))
                c.execute("INSERT INTO app.operational_events(event_code,job_id) VALUES('job_completed',%s)",(job_id,))
            log.info('job_completed duration_seconds=%.2f',time.monotonic()-started)
        except PipelineError as error:
            self.fail(job_id,token,error.code,error.retryable,error.retry_after,error.uncertain)
        except AppError as error:
            self.fail(job_id,token,error.code,False,0,False)
        except Exception as error:
            log.error('job_processing_error type=%s',type(error).__name__)
            # Unknown failures after dispatch may have incurred provider usage.
            self.fail(job_id,token,'processing_error',False,0,True)
        finally:
            heartbeat_stop.set(); thread.join(timeout=2)

    def fail(self,job_id,token,code,retryable,delay,uncertain):
        try:
            with self.db.transaction() as c:
                if retryable:
                    c.execute('SELECT app.retry_analysis_job(%s,%s,%s,%s,%s)',(self.worker_id,token,code,delay,uncertain))
                else:
                    c.execute('SELECT app.fail_analysis_job(%s,%s,%s,%s)',(self.worker_id,token,code,uncertain))
                c.execute("INSERT INTO app.operational_events(event_code,job_id) VALUES(%s,%s)",(code if code.isidentifier() else 'processing_error',job_id))
        except Exception as error:
            # Lease expiry + durable queue recover after a database outage.
            log.error('job_failure_persistence_unavailable type=%s',type(error).__name__)

    def run(self,once=False):
        self.db.open(); self.ops.open()
        idle=0
        try:
            while not self.stop.is_set():
                try:
                    self.tick()
                    idle=0 if self.active else idle+1
                    if once and idle>=5: break
                    self.stop.wait(.2 if self.active else min(5,.25*max(1,idle)))
                except Exception as error:
                    log.error('worker_loop_unavailable type=%s',type(error).__name__)
                    self.stop.wait(5)
                    if once: raise
        finally:
            self.stop.set()
            if self.executor: self.executor.shutdown(wait=True,cancel_futures=False)
            # Earlier resized executors drain their in-flight tasks too.
            for future in self.active:
                try: future.result()
                except Exception: pass
            try:
                with self.db.transaction() as c:
                    c.execute('UPDATE app.worker_heartbeats SET draining=true,last_seen_at=now() WHERE worker_id=%s',(self.worker_id,))
            finally:
                self.db.close(); self.ops.close()

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--once',action='store_true'); args=parser.parse_args()
    logging.basicConfig(level=logging.INFO,format='%(levelname)s %(message)s')
    manager=WorkerManager(get_settings())
    if not manager.settings.worker_database_url.get_secret_value():
        raise SystemExit('Configure WORKER_DATABASE_URL in backend/.env first.')
    signal.signal(signal.SIGINT,lambda *_:manager.stop.set())
    signal.signal(signal.SIGTERM,lambda *_:manager.stop.set())
    manager.run(args.once)

if __name__=='__main__': main()
