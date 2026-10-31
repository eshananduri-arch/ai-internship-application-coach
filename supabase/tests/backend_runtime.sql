-- Development-only synthetic fixtures; no external model calls and no retained data.
BEGIN;
DO $test$
DECLARE owner uuid:=gen_random_uuid(); resume uuid:=gen_random_uuid();
  analysis uuid; job uuid; jobs uuid[]:=ARRAY[]::uuid[];
  worker uuid:=gen_random_uuid(); token uuid; old_token uuid; count_before integer;
  snapshot jsonb; checks integer:=0;
BEGIN
  INSERT INTO app.visitors(id) VALUES(owner);
  INSERT INTO app.resumes(id,visitor_id,file_name,file_type,byte_size,file_sha256,encrypted_original,encryption_key_version)
    VALUES(resume,owner,'runtime-test.docx','docx',10,repeat('a',64),decode('00','hex'),'synthetic-only');
  SELECT count(*) INTO count_before FROM pgmq.q_internship_analysis_jobs;
  FOR i IN 1..10 LOOP
    INSERT INTO app.analyses(visitor_id,resume_id,request_id,company_id,role_id,role_snapshot,candidate_name)
      VALUES(owner,resume,'runtime-'||i,'microsoft','MICROSOFT-01','{}','Test Candidate') RETURNING id INTO analysis;
    INSERT INTO app.analysis_jobs(analysis_id,visitor_id) VALUES(analysis,owner) RETURNING id INTO job;
    jobs:=array_append(jobs,job);
  END LOOP;
  IF (SELECT count(*) FROM pgmq.q_internship_analysis_jobs)<>count_before+10 THEN RAISE EXCEPTION 'Accepted jobs were lost'; END IF;
  checks:=checks+1;
  UPDATE app.worker_settings SET daily_token_budget=0 WHERE singleton;
  IF EXISTS(SELECT 1 FROM app.claim_worker_slot(worker,jobs[1])) THEN RAISE EXCEPTION 'Budget limit ignored'; END IF;
  IF (SELECT attempt_count FROM app.analysis_jobs WHERE id=jobs[1])<>0 THEN RAISE EXCEPTION 'Budget wait consumed attempt'; END IF;
  checks:=checks+2;
  UPDATE app.worker_settings SET daily_token_budget=12000,target_concurrency=2 WHERE singleton;
  SET LOCAL ROLE internship_worker;
  SELECT lease_token INTO token FROM app.claim_worker_slot(worker,jobs[1]);
  IF token IS NULL OR EXISTS(SELECT 1 FROM app.claim_worker_slot(worker,jobs[2])) THEN RAISE EXCEPTION 'Concurrent reservations exceeded budget'; END IF;
  checks:=checks+1;
  IF NOT app.settle_job_usage(worker,token,'test','synthetic',100,50) THEN RAISE EXCEPTION 'Usage settlement failed'; END IF;
  IF NOT app.finish_analysis_job(worker,token,'succeeded') THEN RAISE EXCEPTION 'Completion failed'; END IF;
  RESET ROLE;
  IF (SELECT state FROM app.usage_reservations WHERE lease_token=token)<>'reconciled'
     OR (SELECT input_tokens+output_tokens FROM app.model_usage WHERE job_id=jobs[1])<>150 THEN RAISE EXCEPTION 'Usage accounting mismatch'; END IF;
  checks:=checks+1;
  UPDATE app.worker_settings SET daily_token_budget=100000 WHERE singleton;
  SET LOCAL ROLE internship_worker;
  SELECT lease_token INTO token FROM app.claim_worker_slot(worker,jobs[2]); old_token:=token;
  IF NOT app.retry_analysis_job(worker,token,'provider_throttled',1,false) THEN RAISE EXCEPTION 'Throttle retry failed'; END IF;
  IF EXISTS(SELECT 1 FROM app.claim_worker_slot(worker,jobs[3])) THEN RAISE EXCEPTION 'Provider cooldown ignored'; END IF;
  checks:=checks+1;
  RESET ROLE;
  IF (SELECT status FROM app.analysis_jobs WHERE id=jobs[2])<>'queued'
     OR EXISTS(SELECT 1 FROM app.worker_slots WHERE lease_token=old_token)
     OR EXISTS(SELECT 1 FROM app.usage_reservations WHERE lease_token=old_token) THEN RAISE EXCEPTION 'Retry did not release unused capacity/reservation'; END IF;
  checks:=checks+1;
  UPDATE app.worker_settings SET throttle_until=NULL WHERE singleton;
  UPDATE app.analysis_jobs SET available_at=now() WHERE id=jobs[2];
  SET LOCAL ROLE internship_worker;
  SELECT lease_token INTO token FROM app.claim_worker_slot(worker,jobs[2]);
  IF app.finish_analysis_job(worker,old_token,'succeeded') OR token=old_token THEN RAISE EXCEPTION 'Retried attempt accepted stale token'; END IF;
  IF NOT app.fail_analysis_job(worker,token,'coaching_timeout',true) THEN RAISE EXCEPTION 'Uncertain failure persistence failed'; END IF;
  RESET ROLE;
  IF (SELECT state FROM app.usage_reservations WHERE lease_token=token)<>'unknown' THEN RAISE EXCEPTION 'Unknown provider usage discarded'; END IF;
  checks:=checks+2;
  SET LOCAL ROLE internship_worker;
  SELECT lease_token INTO token FROM app.claim_worker_slot(worker,jobs[3]);
  IF NOT app.fail_analysis_job(worker,token,'extraction_failed',false) THEN RAISE EXCEPTION 'Known non-model failure failed'; END IF;
  RESET ROLE;
  IF EXISTS(SELECT 1 FROM app.usage_reservations WHERE lease_token=token) THEN RAISE EXCEPTION 'Non-model failure consumed budget'; END IF;
  checks:=checks+1;
  UPDATE app.analysis_jobs SET attempt_count=max_attempts WHERE id=jobs[4];
  SET LOCAL ROLE internship_worker;
  IF app.reconcile_jobs()<>1 THEN RAISE EXCEPTION 'Exhausted job recovery failed'; END IF;
  RESET ROLE;
  IF (SELECT status FROM app.analysis_jobs WHERE id=jobs[4])<>'failed'
    OR EXISTS(SELECT 1 FROM pgmq.q_internship_analysis_jobs WHERE message->>'job_id'=jobs[4]::text) THEN RAISE EXCEPTION 'Exhausted job remained in live queue'; END IF;
  checks:=checks+1;
  SET LOCAL ROLE internship_api;
  IF NOT app.consume_rate_limit(repeat('c',64),'upload_owner',1,60)
     OR app.consume_rate_limit(repeat('c',64),'upload_owner',1,60) THEN RAISE EXCEPTION 'Persistent rate limit failed'; END IF;
  checks:=checks+1;
  BEGIN
    PERFORM app.operations_snapshot(); RAISE EXCEPTION 'Visitor accessed operations';
  EXCEPTION WHEN insufficient_privilege THEN checks:=checks+1; END;
  RESET ROLE;
  SET LOCAL ROLE internship_operator;
  SELECT app.operations_snapshot() INTO snapshot;
  IF NOT snapshot ?& ARRAY['settings','jobs','active_slots','workers','tokens_today']
     OR snapshot ? 'resumes' OR snapshot ? 'final_letter' THEN RAISE EXCEPTION 'Unsafe or incomplete operations report'; END IF;
  BEGIN
    PERFORM count(*) FROM app.resumes; RAISE EXCEPTION 'Operator accessed resumes';
  EXCEPTION WHEN insufficient_privilege THEN checks:=checks+1; END;
  RESET ROLE;
  checks:=checks+1;
  PERFORM set_config('test.runtime_checks',checks::text,true);
END $test$;
SELECT current_setting('test.runtime_checks')::integer AS passed_checks;
ROLLBACK;
