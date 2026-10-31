-- Keep pgmq visibility aligned with the database lease, including longer jobs.
CREATE OR REPLACE FUNCTION app.claim_worker_slot(p_worker_id uuid,p_job_id uuid)
RETURNS TABLE(slot_no integer,lease_token uuid,lease_expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $claim$
DECLARE settings app.worker_settings%ROWTYPE; job app.analysis_jobs%ROWTYPE;
  selected_slot integer; token uuid := gen_random_uuid(); expires timestamptz;
BEGIN
  IF p_worker_id IS NULL OR p_job_id IS NULL THEN RETURN; END IF;
  SELECT * INTO settings FROM app.worker_settings WHERE singleton FOR UPDATE;
  IF settings.paused OR settings.target_concurrency=0 THEN RETURN; END IF;
  UPDATE app.worker_slots SET worker_id=NULL,job_id=NULL,lease_token=NULL,lease_expires_at=NULL
    WHERE app.worker_slots.lease_expires_at <= clock_timestamp();
  IF (SELECT count(*) FROM app.worker_slots WHERE job_id IS NOT NULL) >= settings.target_concurrency THEN RETURN; END IF;
  SELECT * INTO job FROM app.analysis_jobs WHERE id=p_job_id FOR UPDATE;
  IF NOT FOUND OR job.status NOT IN ('queued','running') OR job.available_at > clock_timestamp()
     OR job.attempt_count >= job.max_attempts
     OR (job.lease_expires_at IS NOT NULL AND job.lease_expires_at > clock_timestamp()) THEN RETURN; END IF;
  SELECT s.slot_no INTO selected_slot FROM app.worker_slots s WHERE s.job_id IS NULL ORDER BY s.slot_no LIMIT 1 FOR UPDATE;
  expires := clock_timestamp()+make_interval(secs=>settings.lease_seconds);
  UPDATE app.worker_slots s SET worker_id=p_worker_id,job_id=p_job_id,lease_token=token,lease_expires_at=expires
    WHERE s.slot_no=selected_slot;
  UPDATE app.analysis_jobs SET status='running',lease_token=token,lease_expires_at=expires,
    attempt_count=attempt_count+1,updated_at=now() WHERE id=p_job_id;
  PERFORM pgmq.set_vt('internship_analysis_jobs',job.queue_message_id,settings.lease_seconds);
  RETURN QUERY SELECT selected_slot,token,expires;
END
$claim$;

CREATE OR REPLACE FUNCTION app.heartbeat_worker_slot(p_worker_id uuid,p_token uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $heartbeat$
DECLARE duration integer; job uuid; message_id bigint; expires timestamptz;
BEGIN
  SELECT lease_seconds INTO duration FROM app.worker_settings WHERE singleton;
  expires := clock_timestamp()+make_interval(secs=>duration);
  UPDATE app.worker_slots SET lease_expires_at=expires WHERE worker_id=p_worker_id
    AND lease_token=p_token AND lease_expires_at>clock_timestamp() RETURNING job_id INTO job;
  IF job IS NULL THEN RETURN false; END IF;
  UPDATE app.analysis_jobs SET lease_expires_at=expires,updated_at=now() WHERE id=job AND lease_token=p_token
    RETURNING queue_message_id INTO message_id;
  PERFORM pgmq.set_vt('internship_analysis_jobs',message_id,duration);
  RETURN true;
END
$heartbeat$;
