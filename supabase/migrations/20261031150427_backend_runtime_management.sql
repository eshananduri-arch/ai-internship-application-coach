ALTER TABLE app.worker_settings ADD COLUMN auto_manage boolean NOT NULL DEFAULT true,
  ADD COLUMN last_scaled_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN throttle_until timestamptz,
  ADD COLUMN tokens_per_attempt integer NOT NULL DEFAULT 12000 CHECK(tokens_per_attempt BETWEEN 12000 AND 100000);
GRANT UPDATE(auto_manage,last_scaled_at,throttle_until,tokens_per_attempt) ON app.worker_settings TO internship_operator;
CREATE TABLE app.usage_reservations (
  lease_token uuid PRIMARY KEY,
  job_id uuid NOT NULL REFERENCES app.analysis_jobs(id) ON DELETE CASCADE,
  reserved_on date NOT NULL DEFAULT (now() AT TIME ZONE 'UTC')::date,
  tokens integer NOT NULL CHECK(tokens>0),
  state text NOT NULL DEFAULT 'reserved' CHECK(state IN ('reserved','reconciled','unknown'))
);
CREATE INDEX usage_reservations_job_idx ON app.usage_reservations(job_id);
CREATE INDEX usage_reservations_day_idx ON app.usage_reservations(reserved_on,state);
ALTER TABLE app.usage_reservations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON app.usage_reservations FROM PUBLIC,anon,authenticated;
GRANT SELECT ON app.usage_reservations TO internship_operator;
CREATE POLICY operator_reservations ON app.usage_reservations FOR SELECT TO internship_operator USING(true);

ALTER FUNCTION app.claim_worker_slot(uuid,uuid) RENAME TO claim_worker_slot_capacity;
REVOKE ALL ON FUNCTION app.claim_worker_slot_capacity(uuid,uuid) FROM internship_worker;
CREATE FUNCTION app.claim_worker_slot(p_worker_id uuid,p_job_id uuid)
RETURNS TABLE(slot_no integer,lease_token uuid,lease_expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE settings app.worker_settings%ROWTYPE; used bigint; reserved bigint; claimed record;
BEGIN
  SELECT * INTO settings FROM app.worker_settings WHERE singleton FOR UPDATE;
  IF settings.throttle_until>clock_timestamp() THEN RETURN; END IF;
  SELECT coalesce(sum(input_tokens+output_tokens),0) INTO used FROM app.model_usage WHERE created_at>=date_trunc('day',now(),'UTC');
  SELECT coalesce(sum(tokens),0) INTO reserved FROM app.usage_reservations WHERE reserved_on=(now() AT TIME ZONE 'UTC')::date AND state<>'reconciled';
  IF used+reserved+settings.tokens_per_attempt>settings.daily_token_budget THEN RETURN; END IF;
  SELECT * INTO claimed FROM app.claim_worker_slot_capacity(p_worker_id,p_job_id);
  IF NOT FOUND THEN RETURN; END IF;
  INSERT INTO app.usage_reservations(lease_token,job_id,tokens) VALUES(claimed.lease_token,p_job_id,settings.tokens_per_attempt);
  RETURN QUERY SELECT claimed.slot_no,claimed.lease_token,claimed.lease_expires_at;
END $$;

CREATE FUNCTION app.settle_job_usage(p_worker uuid,p_token uuid,p_provider text,p_model text,p_input integer,p_output integer)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job uuid; reserved integer;
BEGIN
  SELECT job_id INTO job FROM app.worker_slots WHERE worker_id=p_worker AND lease_token=p_token AND lease_expires_at>clock_timestamp() FOR UPDATE;
  IF job IS NULL THEN RETURN false; END IF;
  SELECT tokens INTO reserved FROM app.usage_reservations WHERE lease_token=p_token AND state='reserved' FOR UPDATE;
  IF reserved IS NULL OR p_input<0 OR p_output<0 OR p_input+p_output>reserved THEN RAISE EXCEPTION 'Invalid usage settlement'; END IF;
  INSERT INTO app.model_usage(job_id,provider,model,input_tokens,output_tokens) VALUES(job,p_provider,p_model,p_input,p_output);
  UPDATE app.usage_reservations SET state='reconciled' WHERE lease_token=p_token;
  RETURN true;
END $$;

CREATE FUNCTION app.retry_analysis_job(p_worker uuid,p_token uuid,p_code text,p_delay integer,p_uncertain boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job uuid; attempt integer; maximum integer; message_id bigint;
BEGIN
  -- Same lock order as claiming: settings, slot, job.
  PERFORM 1 FROM app.worker_settings WHERE singleton FOR UPDATE;
  SELECT job_id INTO job FROM app.worker_slots WHERE worker_id=p_worker AND lease_token=p_token AND lease_expires_at>clock_timestamp() FOR UPDATE;
  IF job IS NULL THEN RETURN false; END IF;
  SELECT attempt_count,max_attempts,queue_message_id INTO attempt,maximum,message_id FROM app.analysis_jobs WHERE id=job FOR UPDATE;
  IF p_uncertain THEN UPDATE app.usage_reservations SET state='unknown' WHERE lease_token=p_token AND state='reserved';
  ELSE DELETE FROM app.usage_reservations WHERE lease_token=p_token AND state='reserved'; END IF;
  IF p_code='provider_throttled' THEN
    UPDATE app.worker_settings SET throttle_until=clock_timestamp()+make_interval(secs=>least(greatest(p_delay,1),900)),target_concurrency=least(target_concurrency,1) WHERE singleton;
  END IF;
  IF attempt>=maximum THEN
    PERFORM app.finish_analysis_job(p_worker,p_token,'failed',p_code);
    UPDATE app.analyses SET status='failed',stage='Processing failed',failure_code=p_code,updated_at=now() WHERE id=(SELECT analysis_id FROM app.analysis_jobs WHERE id=job);
  ELSE
    UPDATE app.worker_slots SET worker_id=NULL,job_id=NULL,lease_token=NULL,lease_expires_at=NULL WHERE lease_token=p_token;
    UPDATE app.analysis_jobs SET status='queued',lease_token=NULL,lease_expires_at=NULL,last_error_code=p_code,
      available_at=clock_timestamp()+make_interval(secs=>least(greatest(p_delay,1),900)),updated_at=now() WHERE id=job;
    UPDATE app.analyses SET status='queued',stage='Waiting to retry processing',updated_at=now() WHERE id=(SELECT analysis_id FROM app.analysis_jobs WHERE id=job);
    PERFORM pgmq.set_vt('internship_analysis_jobs',message_id,least(greatest(p_delay,1),900));
  END IF;
  RETURN true;
END $$;

CREATE FUNCTION app.defer_unclaimed_job(p_job uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job app.analysis_jobs%ROWTYPE;
BEGIN
  SELECT * INTO job FROM app.analysis_jobs WHERE id=p_job FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF job.status IN ('succeeded','failed','cancelled') THEN PERFORM pgmq.archive('internship_analysis_jobs',job.queue_message_id);
  ELSIF job.status='queued' THEN PERFORM pgmq.set_vt('internship_analysis_jobs',job.queue_message_id,5); END IF;
END $$;

CREATE FUNCTION app.fail_analysis_job(p_worker uuid,p_token uuid,p_code text,p_uncertain boolean) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job uuid;
BEGIN
  SELECT job_id INTO job FROM app.worker_slots WHERE worker_id=p_worker AND lease_token=p_token AND lease_expires_at>clock_timestamp() FOR UPDATE;
  IF job IS NULL THEN RETURN false; END IF;
  IF p_uncertain THEN UPDATE app.usage_reservations SET state='unknown' WHERE lease_token=p_token AND state='reserved';
  ELSE DELETE FROM app.usage_reservations WHERE lease_token=p_token AND state='reserved'; END IF;
  PERFORM app.finish_analysis_job(p_worker,p_token,'failed',p_code);
  UPDATE app.analyses SET status='failed',stage='Processing could not finish',failure_code=p_code,updated_at=now()
    WHERE id=(SELECT analysis_id FROM app.analysis_jobs WHERE id=job);
  RETURN true;
END $$;

CREATE FUNCTION app.reconcile_jobs() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job app.analysis_jobs%ROWTYPE; reconciled integer:=0;
BEGIN
  PERFORM 1 FROM app.worker_settings WHERE singleton FOR UPDATE;
  -- An expired attempt may have consumed tokens; retain its reservation conservatively.
  UPDATE app.usage_reservations r SET state='unknown' FROM app.analysis_jobs j
    WHERE r.lease_token=j.lease_token AND r.state='reserved' AND j.lease_expires_at<=clock_timestamp();
  FOR job IN SELECT * FROM app.analysis_jobs WHERE status IN ('queued','running')
      AND attempt_count>=max_attempts AND (lease_expires_at IS NULL OR lease_expires_at<=clock_timestamp()) FOR UPDATE SKIP LOCKED LOOP
    UPDATE app.worker_slots SET worker_id=NULL,job_id=NULL,lease_token=NULL,lease_expires_at=NULL WHERE job_id=job.id;
    UPDATE app.analysis_jobs SET status='failed',lease_token=NULL,lease_expires_at=NULL,last_error_code='attempts_exhausted',updated_at=now() WHERE id=job.id;
    UPDATE app.analyses SET status='failed',failure_code='attempts_exhausted',stage='Processing attempts exhausted',updated_at=now() WHERE id=job.analysis_id;
    PERFORM pgmq.archive('internship_analysis_jobs',job.queue_message_id);
    reconciled:=reconciled+1;
  END LOOP;
  RETURN reconciled;
END $$;

CREATE TABLE app.rate_limit_windows (
  owner_key text NOT NULL CHECK(owner_key ~ '^[0-9a-f]{64}$'),
  scope text NOT NULL CHECK(scope IN ('session','upload_owner','upload_ip')),
  bucket timestamptz NOT NULL,
  hits integer NOT NULL CHECK(hits>0),
  PRIMARY KEY(owner_key,scope,bucket)
);
CREATE INDEX rate_limit_windows_expiry_idx ON app.rate_limit_windows(bucket);
ALTER TABLE app.rate_limit_windows ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON app.rate_limit_windows FROM PUBLIC,anon,authenticated;
CREATE FUNCTION app.consume_rate_limit(p_key text,p_scope text,p_limit integer,p_seconds integer) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE accepted integer; window_start timestamptz;
BEGIN
  IF p_limit NOT BETWEEN 1 AND 100 OR p_seconds NOT BETWEEN 10 AND 86400 THEN RAISE EXCEPTION 'Invalid rate limit'; END IF;
  window_start:=to_timestamp(floor(extract(epoch FROM now())/p_seconds)*p_seconds);
  INSERT INTO app.rate_limit_windows(owner_key,scope,bucket,hits) VALUES(p_key,p_scope,window_start,1)
    ON CONFLICT(owner_key,scope,bucket) DO UPDATE SET hits=app.rate_limit_windows.hits+1
    WHERE app.rate_limit_windows.hits<p_limit RETURNING hits INTO accepted;
  RETURN accepted IS NOT NULL;
END $$;
-- Authenticated operations aggregates contain no candidate data or letter text.
CREATE FUNCTION app.operations_snapshot() RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
 SELECT jsonb_build_object('settings',(SELECT to_jsonb(s) FROM app.worker_settings s),
 'jobs',(SELECT coalesce(jsonb_object_agg(status,total),'{}') FROM (SELECT status,count(*) total FROM app.analysis_jobs GROUP BY status) counts),
 'active_slots',(SELECT count(*) FROM app.worker_slots WHERE lease_expires_at>clock_timestamp()),
 'workers',(SELECT count(*) FROM app.worker_heartbeats WHERE last_seen_at>now()-interval '60 seconds'),
 'oldest_queued_seconds',(SELECT coalesce(extract(epoch FROM now()-min(created_at)),0) FROM app.analysis_jobs WHERE status='queued'),
 'tokens_today',(SELECT coalesce(sum(input_tokens+output_tokens),0) FROM app.model_usage WHERE created_at>=date_trunc('day',now(),'UTC')),
 'reserved_or_unknown_tokens',(SELECT coalesce(sum(tokens),0) FROM app.usage_reservations WHERE state<>'reconciled' AND reserved_on=(now() AT TIME ZONE 'UTC')::date))
$$;
REVOKE ALL ON FUNCTION app.claim_worker_slot(uuid,uuid),app.settle_job_usage(uuid,uuid,text,text,integer,integer),
 app.retry_analysis_job(uuid,uuid,text,integer,boolean),app.defer_unclaimed_job(uuid),app.fail_analysis_job(uuid,uuid,text,boolean),app.reconcile_jobs(),
 app.consume_rate_limit(text,text,integer,integer),app.operations_snapshot() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.claim_worker_slot(uuid,uuid),app.settle_job_usage(uuid,uuid,text,text,integer,integer),
 app.retry_analysis_job(uuid,uuid,text,integer,boolean),app.defer_unclaimed_job(uuid),app.fail_analysis_job(uuid,uuid,text,boolean),app.reconcile_jobs() TO internship_worker;
GRANT EXECUTE ON FUNCTION app.consume_rate_limit(text,text,integer,integer) TO internship_api;
GRANT EXECUTE ON FUNCTION app.operations_snapshot() TO internship_operator;
