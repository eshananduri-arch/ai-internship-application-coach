-- Run as the migration administrator against a development database.
-- All fixtures, queue messages and setting changes are rolled back.
BEGIN;
DO $tests$
DECLARE owner_a uuid:=gen_random_uuid(); owner_b uuid:=gen_random_uuid();
  resume_a uuid:=gen_random_uuid(); resume_b uuid:=gen_random_uuid();
  analysis_a uuid:=gen_random_uuid(); analysis_b uuid:=gen_random_uuid();
  decision_a uuid; application_a uuid; job_ids uuid[]:=ARRAY[]::uuid[];
  a uuid; j uuid; token_a uuid; token_b uuid; token_new uuid;
  worker_a uuid:=gen_random_uuid(); worker_b uuid:=gen_random_uuid();
  letter text:=E'Dear Hiring Team,\n\nI am applying for this simulated internship. My projects demonstrate relevant programming and analytical skills. I would welcome the opportunity to contribute and learn.\n\nSincerely,\nTest Candidate';
  passed integer:=0; n integer; result boolean;
BEGIN
  IF (SELECT count(*) FROM public.companies)<>5 OR (SELECT count(*) FROM public.internship_roles)<>15
    OR (SELECT count(*) FROM public.role_documents)<>5 THEN RAISE EXCEPTION 'Catalog seed mismatch'; END IF;
  IF EXISTS(SELECT 1 FROM public.companies c WHERE (SELECT count(*) FROM public.internship_roles r WHERE r.company_id=c.company_id)<>3)
    THEN RAISE EXCEPTION 'Every company must have three roles'; END IF;
  passed:=passed+2;
  IF EXISTS(SELECT 1 FROM public.role_documents WHERE index_status<>'pending')
    OR EXISTS(SELECT 1 FROM public.internship_role_chunks) THEN RAISE EXCEPTION 'Unindexed sources must not pretend to be ready'; END IF;
  passed:=passed+1;
  IF app.letter_sha256(E'one\r\ntwo')<>app.letter_sha256(E'one\ntwo') THEN RAISE EXCEPTION 'Line ending hashes differ'; END IF;
  passed:=passed+1;
  IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
      WHERE s.nspname IN ('app','public') AND c.relkind='r' AND NOT c.relrowsecurity) THEN RAISE EXCEPTION 'Missing RLS'; END IF;
  passed:=passed+1;
  IF has_schema_privilege('anon','app','USAGE') OR has_schema_privilege('authenticated','app','USAGE')
    OR has_schema_privilege('anon','pgmq','USAGE') THEN RAISE EXCEPTION 'Private schema grants'; END IF;
  IF has_table_privilege('anon','public.internship_roles','SELECT')
    OR has_function_privilege('anon','app.claim_worker_slot(uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'Anonymous grants'; END IF;
  passed:=passed+2;

  INSERT INTO app.visitors(id) VALUES(owner_a),(owner_b);
  INSERT INTO app.resumes(id,visitor_id,file_name,file_type,byte_size,file_sha256,encrypted_original,encryption_key_version)
    VALUES(resume_a,owner_a,'test-a.docx','docx',10,repeat('a',64),decode('00','hex'),'test-only'),
          (resume_b,owner_b,'test-b.pdf','pdf',10,repeat('b',64),decode('00','hex'),'test-only');
  INSERT INTO app.analyses(id,visitor_id,resume_id,request_id,company_id,role_id,role_snapshot,candidate_name,status,draft_version,final_letter,approval_allowed)
    VALUES(analysis_a,owner_a,resume_a,'test-approve','microsoft','MICROSOFT-01','{"role_id":"MICROSOFT-01"}','Test Candidate','ready',1,letter,true),
          (analysis_b,owner_a,resume_a,'test-reject','microsoft','MICROSOFT-01','{"role_id":"MICROSOFT-01"}','Test Candidate','ready',1,letter,true);
  BEGIN
    INSERT INTO app.analyses(visitor_id,resume_id,request_id,company_id,role_id,role_snapshot,candidate_name)
      VALUES(owner_a,resume_b,'bad-owner','microsoft','MICROSOFT-01','{}','Test Candidate');
    RAISE EXCEPTION 'Cross-owner resume accepted';
  EXCEPTION WHEN foreign_key_violation THEN passed:=passed+1; END;
  BEGIN
    INSERT INTO app.analyses(visitor_id,resume_id,request_id,company_id,role_id,role_snapshot,candidate_name)
      VALUES(owner_a,resume_a,'bad-role','google','MICROSOFT-01','{}','Test Candidate');
    RAISE EXCEPTION 'Mismatched company and role accepted';
  EXCEPTION WHEN foreign_key_violation THEN passed:=passed+1; END;

  PERFORM set_config('app.visitor_id',owner_a::text,true);
  SET LOCAL ROLE internship_api;
  IF (SELECT count(*) FROM app.resumes)<>1 OR (SELECT count(*) FROM app.analyses)<>2 THEN RAISE EXCEPTION 'Owner A isolation failed'; END IF;
  passed:=passed+1;
  PERFORM set_config('app.visitor_id',owner_b::text,true);
  IF (SELECT count(*) FROM app.resumes)<>1 OR EXISTS(SELECT 1 FROM app.analyses) THEN RAISE EXCEPTION 'Owner B isolation failed'; END IF;
  passed:=passed+1;
  PERFORM set_config('app.visitor_id','',true);
  IF EXISTS(SELECT 1 FROM app.resumes) THEN RAISE EXCEPTION 'Missing owner context exposed rows'; END IF;
  passed:=passed+1;
  PERFORM set_config('app.visitor_id',owner_a::text,true);
  BEGIN
    INSERT INTO app.approval_decisions(analysis_id,visitor_id,decision,human_confirmed,draft_version,final_letter,idempotency_key)
      VALUES(analysis_a,owner_a,'approve',false,1,letter,'bad-confirm');
    RAISE EXCEPTION 'Approval without confirmation accepted';
  EXCEPTION WHEN check_violation THEN passed:=passed+1; END;
  BEGIN
    INSERT INTO app.approval_decisions(analysis_id,visitor_id,decision,human_confirmed,draft_version,final_letter,idempotency_key)
      VALUES(analysis_a,owner_a,'approve',true,2,letter,'bad-version');
    RAISE EXCEPTION 'Stale draft version accepted';
  EXCEPTION WHEN check_violation THEN passed:=passed+1; END;
  INSERT INTO app.approval_decisions(analysis_id,visitor_id,decision,human_confirmed,draft_version,final_letter,idempotency_key)
    VALUES(analysis_a,owner_a,'approve',true,1,letter,'good-approve') RETURNING id INTO decision_a;
  BEGIN
    INSERT INTO app.applications(visitor_id,analysis_id,decision_id,role_snapshot,final_letter)
      VALUES(owner_a,analysis_a,decision_a,'{"role_id":"MICROSOFT-01"}',letter||' Changed.');
    RAISE EXCEPTION 'Unapproved changed text accepted';
  EXCEPTION WHEN check_violation THEN passed:=passed+1; END;
  BEGIN
    INSERT INTO app.applications(visitor_id,analysis_id,decision_id,role_snapshot,final_letter)
      VALUES(owner_a,analysis_a,decision_a,'{"role_id":"GOOGLE-01"}',letter);
    RAISE EXCEPTION 'Wrong role snapshot accepted';
  EXCEPTION WHEN check_violation THEN passed:=passed+1; END;
  INSERT INTO app.applications(visitor_id,analysis_id,decision_id,role_snapshot,final_letter)
    VALUES(owner_a,analysis_a,decision_a,'{"role_id":"MICROSOFT-01"}',letter) RETURNING id INTO application_a;
  passed:=passed+1;
  BEGIN
    UPDATE app.applications SET final_letter=letter||' Changed.' WHERE id=application_a;
    RAISE EXCEPTION 'Approved letter was mutable';
  EXCEPTION WHEN check_violation THEN passed:=passed+1; END;
  BEGIN
    UPDATE app.approval_decisions SET human_confirmed=false WHERE id=decision_a;
    RAISE EXCEPTION 'Decision was mutable';
  EXCEPTION WHEN check_violation THEN passed:=passed+1; END;
  INSERT INTO app.approval_decisions(analysis_id,visitor_id,decision,draft_version,final_letter,idempotency_key)
    VALUES(analysis_b,owner_a,'reject',1,letter,'good-reject') RETURNING id INTO decision_a;
  BEGIN
    INSERT INTO app.applications(visitor_id,analysis_id,decision_id,role_snapshot,final_letter)
      VALUES(owner_a,analysis_b,decision_a,'{"role_id":"MICROSOFT-01"}',letter);
    RAISE EXCEPTION 'Rejected application was saved';
  EXCEPTION WHEN check_violation THEN passed:=passed+1; END;
  PERFORM set_config('app.visitor_id',owner_b::text,true);
  IF EXISTS(SELECT 1 FROM app.applications) THEN RAISE EXCEPTION 'Cross-owner application exposed'; END IF;
  passed:=passed+1;
  RESET ROLE;

  -- Queue insertion rolls back with its job; forced exception is a subtransaction.
  SELECT count(*) INTO n FROM pgmq.q_internship_analysis_jobs;
  BEGIN
    INSERT INTO app.analysis_jobs(analysis_id,visitor_id) VALUES(analysis_b,owner_a);
    RAISE EXCEPTION 'force rollback' USING ERRCODE='P0002';
  EXCEPTION WHEN no_data_found THEN NULL; END;
  IF (SELECT count(*) FROM pgmq.q_internship_analysis_jobs)<>n THEN RAISE EXCEPTION 'Queue message escaped transaction rollback'; END IF;
  passed:=passed+1;
  FOR i IN 1..3 LOOP
    a:=gen_random_uuid();
    INSERT INTO app.analyses(id,visitor_id,resume_id,request_id,company_id,role_id,role_snapshot,candidate_name)
      VALUES(a,owner_a,resume_a,'queue-test-'||i,'nvidia','NVIDIA-01','{}','Test Candidate');
    INSERT INTO app.analysis_jobs(analysis_id,visitor_id) VALUES(a,owner_a) RETURNING id INTO j;
    job_ids:=array_append(job_ids,j);
  END LOOP;
  IF (SELECT count(*) FROM pgmq.q_internship_analysis_jobs)<>n+3
    OR EXISTS(SELECT 1 FROM pgmq.q_internship_analysis_jobs WHERE (SELECT count(*) FROM jsonb_object_keys(message))<>1 OR NOT message ? 'job_id')
    THEN RAISE EXCEPTION 'Queue payload or enqueue count failed'; END IF;
  passed:=passed+1;
  SET LOCAL ROLE internship_worker;
  IF (SELECT count(*) FROM app.read_analysis_queue(3))<>3 THEN RAISE EXCEPTION 'Queue reader failed'; END IF;
  passed:=passed+1;
  SELECT lease_token INTO token_a FROM app.claim_worker_slot(worker_a,job_ids[1]);
  SELECT lease_token INTO token_b FROM app.claim_worker_slot(worker_b,job_ids[2]);
  IF token_a IS NULL OR token_b IS NOT NULL THEN RAISE EXCEPTION 'Default single global slot not enforced'; END IF;
  passed:=passed+1;
  RESET ROLE;
  UPDATE app.worker_settings SET target_concurrency=2 WHERE singleton;
  SET LOCAL ROLE internship_worker;
  SELECT lease_token INTO token_b FROM app.claim_worker_slot(worker_b,job_ids[2]);
  IF token_b IS NULL OR EXISTS(SELECT 1 FROM app.claim_worker_slot(gen_random_uuid(),job_ids[3]))
    THEN RAISE EXCEPTION 'Global maximum two slots not enforced'; END IF;
  passed:=passed+1;
  IF app.finish_analysis_job(worker_b,token_a,'succeeded') THEN RAISE EXCEPTION 'Wrong worker released slot'; END IF;
  IF NOT app.heartbeat_worker_slot(worker_a,token_a) THEN RAISE EXCEPTION 'Valid heartbeat failed'; END IF;
  passed:=passed+2;
  RESET ROLE;
  UPDATE app.worker_slots SET lease_expires_at=clock_timestamp()-interval '1 second' WHERE lease_token=token_a;
  UPDATE app.analysis_jobs SET lease_expires_at=clock_timestamp()-interval '1 second' WHERE lease_token=token_a;
  SET LOCAL ROLE internship_worker;
  SELECT lease_token INTO token_new FROM app.claim_worker_slot(worker_a,job_ids[1]);
  IF token_new IS NULL OR token_new=token_a OR app.heartbeat_worker_slot(worker_a,token_a)
     OR app.finish_analysis_job(worker_a,token_a,'succeeded') THEN RAISE EXCEPTION 'Stale token fencing failed'; END IF;
  passed:=passed+1;
  IF NOT app.finish_analysis_job(worker_a,token_new,'succeeded') THEN RAISE EXCEPTION 'Job completion failed'; END IF;
  IF app.finish_analysis_job(worker_a,token_new,'succeeded') THEN RAISE EXCEPTION 'Duplicate completion accepted'; END IF;
  passed:=passed+2;
  RESET ROLE;
  IF EXISTS(SELECT 1 FROM pgmq.q_internship_analysis_jobs WHERE message->>'job_id'=job_ids[1]::text)
    OR NOT EXISTS(SELECT 1 FROM pgmq.a_internship_analysis_jobs WHERE message->>'job_id'=job_ids[1]::text)
    THEN RAISE EXCEPTION 'Terminal message was not archived'; END IF;
  passed:=passed+1;
  UPDATE app.worker_settings SET paused=true WHERE singleton;
  IF EXISTS(SELECT 1 FROM app.claim_worker_slot(worker_a,job_ids[3])) THEN RAISE EXCEPTION 'Pause ignored'; END IF;
  passed:=passed+1;
  SET LOCAL ROLE internship_mcp_reader;
  IF (SELECT count(*) FROM public.internship_role_chunks)<>0 THEN RAISE EXCEPTION 'Unexpected embeddings'; END IF;
  BEGIN
    PERFORM count(*) FROM app.resumes;
    RAISE EXCEPTION 'MCP can access resumes';
  EXCEPTION WHEN insufficient_privilege THEN passed:=passed+1; END;
  RESET ROLE;
  PERFORM set_config('test.database_v1_passed',passed::text,true);
END
$tests$;
SELECT current_setting('test.database_v1_passed')::integer AS passed_checks,
  'All synthetic records and queue messages rolled back' AS fixture_policy;
ROLLBACK;
