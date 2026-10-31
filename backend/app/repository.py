import hashlib
import json
from uuid import UUID, uuid4
from psycopg.types.json import Jsonb
from .coaching import validate_letter, normalize_letter
from .errors import AppError
from .security import digest

def json_hash(value):
    return digest(json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False))

def missing():
    raise AppError('This record was not found in your private session.',404,'not_found')

class Repository:
    def __init__(self, db, encryption, settings):
        self.db,self.encryption,self.settings=db,encryption,settings

    def rate_limit(self,key,scope,limit,seconds):
        with self.db.transaction() as c:
            okay=c.execute('SELECT app.consume_rate_limit(%s,%s,%s,%s) AS ok',(key,scope,limit,seconds)).fetchone()['ok']
        if not okay:
            raise AppError('Too many requests. Please wait before trying again.',429,'rate_limited')

    def companies(self):
        with self.db.transaction() as c:
            return c.execute('SELECT name FROM public.companies WHERE active ORDER BY name').fetchall()

    def roles(self,company):
        with self.db.transaction() as c:
            rows=c.execute('''SELECT r.role_id,c.name company,r.role_title role,r.location,r.deadline
                FROM public.internship_roles r JOIN public.companies c USING(company_id)
                WHERE c.name=%s AND c.active AND r.active ORDER BY r.role_id''',(company,)).fetchall()
        return rows

    def submit(self,owner,fields,name,file_type,data):
        payload_hash=json_hash({**fields,'file_sha256':digest(data),'file_name':name})
        request_key=fields['request_id']
        encrypted=self.encryption.encrypt(data)
        with self.db.transaction(owner) as c:
            # Serializes only duplicate submissions from this visitor/key.
            c.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s,0))',(str(owner)+':'+request_key,))
            previous=c.execute("SELECT * FROM app.idempotency_requests WHERE visitor_id=%s AND route='create_analysis' AND request_key=%s",(owner,request_key)).fetchone()
            if previous:
                if previous['payload_sha256']!=payload_hash:
                    raise AppError('This request key was already used for another submission.',409,'idempotency_conflict')
                return {'analysis_id':str(previous['analysis_id']),'status':'queued','stage':'Your submission is already saved'}
            role=c.execute('''SELECT r.*,c.name company FROM public.internship_roles r JOIN public.companies c USING(company_id)
                WHERE r.role_id=%s AND c.name=%s AND r.active AND c.active''',(fields['role_id'],fields['company'])).fetchone()
            if not role or role['role_title']!=fields['role_title']:
                raise AppError('Select a valid company and role from the catalog.',422,'role_mismatch')
            # Recheck deadlines at submission using the same India calendar as tools.
            if c.execute("SELECT %s::date < (now() AT TIME ZONE 'Asia/Kolkata')::date AS expired",(role['deadline'],)).fetchone()['expired']:
                raise AppError('This demo role deadline has passed. Select another role.',422,'role_expired')
            snapshot={k:role[k] for k in ('company','role_id','role_title','location','required_skills','preferred_skills','catalog_version')}
            snapshot['deadline']=role['deadline'].isoformat()
            snapshot['is_fictional']=True
            resume=c.execute('''INSERT INTO app.resumes(visitor_id,file_name,file_type,byte_size,file_sha256,encrypted_original,encryption_key_version)
                VALUES(%s,%s,%s,%s,%s,%s,%s) RETURNING id''',(owner,name,file_type,len(data),digest(data),encrypted,self.settings.encryption_key_version)).fetchone()['id']
            analysis=c.execute('''INSERT INTO app.analyses(visitor_id,resume_id,request_id,company_id,role_id,role_snapshot,candidate_name)
                VALUES(%s,%s,%s,%s,%s,%s,%s) RETURNING id''',(owner,resume,request_key,role['company_id'],role['role_id'],Jsonb(snapshot),fields['candidate_name'])).fetchone()['id']
            c.execute('INSERT INTO app.analysis_jobs(analysis_id,visitor_id) VALUES(%s,%s)',(analysis,owner))
            c.execute('''INSERT INTO app.idempotency_requests(visitor_id,route,request_key,payload_sha256,analysis_id,http_status)
                VALUES(%s,'create_analysis',%s,%s,%s,202)''',(owner,request_key,payload_hash,analysis))
        return {'analysis_id':str(analysis),'status':'queued','stage':'Resume securely saved; waiting for a worker'}

    def status(self,owner,analysis_id):
        with self.db.transaction(owner) as c:
            row=c.execute('SELECT * FROM app.analyses WHERE id=%s',(analysis_id,)).fetchone()
            if not row: missing()
            result={'analysis_id':str(row['id']),'status':row['status'],'stage':row['stage']}
            if row['status'] in ('ready','approved','rejected'):
                result['result']={'company':row['role_snapshot']['company'],'role_id':row['role_id'],
                    'final_letter':row['final_letter'],'draft_version':row['draft_version'],
                    'approval_allowed':row['approval_allowed'],'critic_review':row['critic_review'],
                    'match_report':row['match_report'],'deadline_info':row['deadline_info']}
            if row['status'] in ('failed','blocked','cancelled'):
                result['status']='failed'
                result['message']=failure_message(row['failure_code'])
            if row['status']=='approved':
                app=c.execute('SELECT id FROM app.applications WHERE analysis_id=%s',(analysis_id,)).fetchone()
                result['application_id']=str(app['id']) if app else None
        return result

    def recent(self,owner):
        with self.db.transaction(owner) as c:
            return c.execute('''SELECT a.id analysis_id,a.status,a.created_at,a.role_id,a.role_snapshot->>'company' company,
                a.role_snapshot->>'role_title' role_title,p.id application_id FROM app.analyses a LEFT JOIN app.applications p ON p.analysis_id=a.id
                ORDER BY a.created_at DESC LIMIT 20''').fetchall()

    def decide(self,owner,analysis_id,body,key):
        payload={**body,'final_letter':normalize_letter(body['final_letter'])}
        checksum=json_hash(payload)
        with self.db.transaction(owner) as c:
            row=c.execute('SELECT * FROM app.analyses WHERE id=%s FOR UPDATE',(analysis_id,)).fetchone()
            if not row: missing()
            previous=c.execute("SELECT * FROM app.idempotency_requests WHERE visitor_id=%s AND route='decision' AND request_key=%s",(owner,key)).fetchone()
            if previous:
                if previous['payload_sha256']!=checksum or previous['analysis_id']!=analysis_id:
                    raise AppError('This decision key was already used for other content.',409,'idempotency_conflict')
                return self._receipt(c,analysis_id)
            if row['status']!='ready' or row['draft_version']!=body['draft_version']:
                raise AppError('This draft has changed or already received a decision. Reload its status.',409,'draft_conflict')
            if body['decision']=='approve':
                if not row['approval_allowed']:
                    raise AppError('This draft requires review before approval.',409,'approval_blocked')
                payload['final_letter']=validate_letter(payload['final_letter'],row['candidate_name'])
            elif payload['final_letter']!=normalize_letter(row['final_letter']):
                # Rejection may include edits for the audit but is never exported.
                if not 1<=len(payload['final_letter'])<=20000:
                    raise AppError('Invalid rejected draft.',422)
            decision=c.execute('''INSERT INTO app.approval_decisions(analysis_id,visitor_id,decision,human_confirmed,draft_version,final_letter,idempotency_key)
                VALUES(%s,%s,%s,%s,%s,%s,%s) RETURNING id''',(analysis_id,owner,body['decision'],body['decision']=='approve',body['draft_version'],payload['final_letter'],key)).fetchone()['id']
            application=None
            state='rejected'
            if body['decision']=='approve':
                application=c.execute('''INSERT INTO app.applications(visitor_id,analysis_id,decision_id,role_snapshot,final_letter)
                    VALUES(%s,%s,%s,%s,%s) RETURNING id''',(owner,analysis_id,decision,Jsonb(row['role_snapshot']),payload['final_letter'])).fetchone()['id']
                state='approved'
            c.execute('UPDATE app.analyses SET status=%s,stage=%s,updated_at=now() WHERE id=%s',(state,state.title(),analysis_id))
            c.execute('''INSERT INTO app.idempotency_requests(visitor_id,route,request_key,payload_sha256,analysis_id,application_id,http_status)
                VALUES(%s,'decision',%s,%s,%s,%s,200)''',(owner,key,checksum,analysis_id,application))
            return self._receipt(c,analysis_id)

    def _receipt(self,c,analysis):
        decision=c.execute('SELECT decision,final_letter FROM app.approval_decisions WHERE analysis_id=%s',(analysis,)).fetchone()
        if decision['decision']=='reject': return {'status':'rejected'}
        app=c.execute('SELECT id,final_letter FROM app.applications WHERE analysis_id=%s',(analysis,)).fetchone()
        return {'status':'approved','application_id':str(app['id']),'final_letter':app['final_letter']}

    def application(self,owner,application_id):
        with self.db.transaction(owner) as c:
            row=c.execute('SELECT * FROM app.applications WHERE id=%s',(application_id,)).fetchone()
            if not row: missing()
            return row

def failure_message(code):
    return {'extraction_failed':'Could not read this resume. Use a text-based PDF or DOCX.',
        'coaching_unconfigured':'The coaching workflow is not connected yet.',
        'provider_throttled':'The AI provider is busy. Processing attempts were exhausted; please try later.',
        'missing_role_evidence':'The workflow did not return verified role search evidence.',
        'missing_final_letter_evidence':'The workflow did not verify the exact final letter.',
        'critic_requires_changes':'The reviewer requested changes. This draft cannot be approved.',
        'coaching_timeout':'The coaching service timed out. No application was approved.'}.get(code,'Processing could not finish safely. No application was approved. Please try again later.')
