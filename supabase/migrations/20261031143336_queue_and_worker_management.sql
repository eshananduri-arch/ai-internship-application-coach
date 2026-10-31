-- Queue payloads contain identifiers only. Python workers are implemented separately.
CREATE EXTENSION IF NOT EXISTS pgmq;
SELECT pgmq.create('internship_analysis_jobs');
REVOKE ALL ON SCHEMA pgmq FROM PUBLIC,anon,authenticated;

CREATE TABLE app.analysis_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  analysis_id uuid NOT NULL UNIQUE,
  visitor_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','running','succeeded','failed','cancelled')),
  queue_message_id bigint UNIQUE,
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count BETWEEN 0 AND 5),
  max_attempts integer NOT NULL DEFAULT 3 CHECK (max_attempts BETWEEN 1 AND 5),
  available_at timestamptz NOT NULL DEFAULT now(),
  lease_token uuid,
  lease_expires_at timestamptz,
  last_error_code text CHECK (char_length(last_error_code) <= 100),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(id,visitor_id),
  FOREIGN KEY(analysis_id,visitor_id) REFERENCES app.analyses(id,visitor_id) ON DELETE CASCADE,
  CHECK ((lease_token IS NULL) = (lease_expires_at IS NULL)),
  CHECK (status <> 'running' OR lease_token IS NOT NULL)
);
CREATE INDEX analysis_jobs_owner_idx ON app.analysis_jobs(visitor_id,created_at DESC);
CREATE INDEX analysis_jobs_pending_idx ON app.analysis_jobs(status,available_at);

CREATE TABLE app.worker_settings (
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  paused boolean NOT NULL DEFAULT false,
  min_concurrency integer NOT NULL DEFAULT 1,
  target_concurrency integer NOT NULL DEFAULT 1,
  max_concurrency integer NOT NULL DEFAULT 2,
  backlog_per_slot integer NOT NULL DEFAULT 3 CHECK(backlog_per_slot BETWEEN 1 AND 100),
  cooldown_seconds integer NOT NULL DEFAULT 60 CHECK(cooldown_seconds BETWEEN 10 AND 3600),
  lease_seconds integer NOT NULL DEFAULT 120 CHECK(lease_seconds BETWEEN 30 AND 900),
  daily_token_budget bigint NOT NULL DEFAULT 100000 CHECK(daily_token_budget >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK(0 <= min_concurrency AND min_concurrency <= target_concurrency
        AND target_concurrency <= max_concurrency AND max_concurrency <= 16)
);
INSERT INTO app.worker_settings(singleton) VALUES(true);

CREATE TABLE app.worker_slots (
  slot_no integer PRIMARY KEY CHECK(slot_no BETWEEN 1 AND 16),
  worker_id uuid,
  job_id uuid UNIQUE REFERENCES app.analysis_jobs(id),
  lease_token uuid UNIQUE,
  lease_expires_at timestamptz,
  CHECK ((worker_id IS NULL AND job_id IS NULL AND lease_token IS NULL AND lease_expires_at IS NULL)
      OR (worker_id IS NOT NULL AND job_id IS NOT NULL AND lease_token IS NOT NULL AND lease_expires_at IS NOT NULL))
);
INSERT INTO app.worker_slots(slot_no) SELECT generate_series(1,16);

CREATE TABLE app.worker_heartbeats (
  worker_id uuid PRIMARY KEY,
  started_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  draining boolean NOT NULL DEFAULT false
);
CREATE TABLE app.operational_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_code text NOT NULL CHECK(event_code ~ '^[a-z][a-z0-9_]{1,99}$'),
  job_id uuid REFERENCES app.analysis_jobs(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX operational_events_job_idx ON app.operational_events(job_id);
CREATE INDEX operational_events_created_idx ON app.operational_events(created_at);
CREATE TABLE app.model_usage (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  job_id uuid REFERENCES app.analysis_jobs(id) ON DELETE SET NULL,
  provider text NOT NULL CHECK(char_length(provider) BETWEEN 1 AND 100),
  model text NOT NULL CHECK(char_length(model) BETWEEN 1 AND 100),
  input_tokens integer NOT NULL CHECK(input_tokens >= 0),
  output_tokens integer NOT NULL CHECK(output_tokens >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX model_usage_job_idx ON app.model_usage(job_id);
CREATE INDEX model_usage_created_idx ON app.model_usage(created_at);

-- Creating the job and sending its queue message commit or roll back together.
CREATE FUNCTION app.enqueue_analysis_job() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $enqueue$
DECLARE message_id bigint;
BEGIN
  SELECT pgmq.send('internship_analysis_jobs',jsonb_build_object('job_id',NEW.id)) INTO message_id;
  UPDATE app.analysis_jobs SET queue_message_id=message_id WHERE id=NEW.id;
  RETURN NEW;
END
$enqueue$;
CREATE TRIGGER enqueue_analysis AFTER INSERT ON app.analysis_jobs
  FOR EACH ROW EXECUTE FUNCTION app.enqueue_analysis_job();

-- One locked settings row serializes capacity decisions across every worker process.
-- Expired tokens cannot heartbeat or release the replacement owner's slot.
CREATE FUNCTION app.claim_worker_slot(p_worker_id uuid,p_job_id uuid)
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
  RETURN QUERY SELECT selected_slot,token,expires;
END
$claim$;

CREATE FUNCTION app.heartbeat_worker_slot(p_worker_id uuid,p_token uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $heartbeat$
DECLARE duration integer; job uuid; expires timestamptz;
BEGIN
  SELECT lease_seconds INTO duration FROM app.worker_settings WHERE singleton;
  expires := clock_timestamp()+make_interval(secs=>duration);
  UPDATE app.worker_slots SET lease_expires_at=expires WHERE worker_id=p_worker_id
    AND lease_token=p_token AND lease_expires_at>clock_timestamp() RETURNING job_id INTO job;
  IF job IS NULL THEN RETURN false; END IF;
  UPDATE app.analysis_jobs SET lease_expires_at=expires,updated_at=now() WHERE id=job AND lease_token=p_token;
  RETURN true;
END
$heartbeat$;

-- Terminal state and queue acknowledgement share a transaction. Results must be
-- persisted by Python in this same transaction only after this fencing check succeeds.
CREATE FUNCTION app.finish_analysis_job(p_worker_id uuid,p_token uuid,p_status text,p_error_code text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $finish$
DECLARE message_id bigint;
BEGIN
  IF p_status NOT IN ('succeeded','failed','cancelled') THEN RAISE EXCEPTION 'Invalid terminal job status'; END IF;
  UPDATE app.worker_slots SET worker_id=NULL,job_id=NULL,lease_token=NULL,lease_expires_at=NULL
    WHERE worker_id=p_worker_id AND lease_token=p_token AND lease_expires_at>clock_timestamp()
    ;
  IF NOT FOUND THEN RETURN false; END IF;
  UPDATE app.analysis_jobs SET status=p_status,lease_token=NULL,lease_expires_at=NULL,
    last_error_code=p_error_code,updated_at=now() WHERE lease_token=p_token
    RETURNING queue_message_id INTO message_id;
  IF message_id IS NULL THEN RAISE EXCEPTION 'Missing fenced job'; END IF;
  PERFORM pgmq.archive('internship_analysis_jobs',message_id);
  RETURN true;
END
$finish$;

CREATE FUNCTION app.read_analysis_queue(p_count integer DEFAULT 1)
RETURNS TABLE(msg_id bigint,read_ct integer,enqueued_at timestamptz,vt timestamptz,message jsonb)
LANGUAGE sql SECURITY DEFINER SET search_path = ''
AS $$ SELECT q.msg_id,q.read_ct,q.enqueued_at,q.vt,q.message
      FROM pgmq.read('internship_analysis_jobs',120,least(greatest(p_count,1),16)) q $$;

-- Failed delivery is retried by visibility timeout; the worker also checks the
-- persisted job status and attempt limit. A controller must terminalize exhausted jobs.
REVOKE ALL ON FUNCTION app.enqueue_analysis_job(),app.claim_worker_slot(uuid,uuid),
  app.heartbeat_worker_slot(uuid,uuid),app.finish_analysis_job(uuid,uuid,text,text),
  app.read_analysis_queue(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.claim_worker_slot(uuid,uuid),app.heartbeat_worker_slot(uuid,uuid),
  app.finish_analysis_job(uuid,uuid,text,text),app.read_analysis_queue(integer) TO internship_worker;

DO $security$
DECLARE name text;
BEGIN
  FOREACH name IN ARRAY ARRAY['analysis_jobs','worker_settings','worker_slots','worker_heartbeats','operational_events','model_usage'] LOOP
    EXECUTE format('ALTER TABLE app.%I ENABLE ROW LEVEL SECURITY',name);
    EXECUTE format('REVOKE ALL ON app.%I FROM PUBLIC,anon,authenticated',name);
  END LOOP;
END
$security$;
GRANT SELECT,INSERT ON app.analysis_jobs TO internship_api;
CREATE POLICY job_ownership ON app.analysis_jobs TO internship_api
  USING(visitor_id=app.current_visitor_id()) WITH CHECK(visitor_id=app.current_visitor_id());
GRANT SELECT ON app.analysis_jobs,app.worker_settings TO internship_worker;
CREATE POLICY worker_jobs ON app.analysis_jobs FOR SELECT TO internship_worker USING(true);
CREATE POLICY worker_settings_read ON app.worker_settings FOR SELECT TO internship_worker USING(true);
GRANT SELECT,INSERT,UPDATE ON app.worker_heartbeats TO internship_worker;
CREATE POLICY worker_heartbeat_write ON app.worker_heartbeats TO internship_worker USING(true) WITH CHECK(true);
GRANT INSERT ON app.operational_events,app.model_usage TO internship_worker;
GRANT USAGE ON SEQUENCE app.operational_events_id_seq,app.model_usage_id_seq TO internship_worker;
CREATE POLICY worker_event_write ON app.operational_events FOR INSERT TO internship_worker WITH CHECK(true);
CREATE POLICY worker_usage_write ON app.model_usage FOR INSERT TO internship_worker WITH CHECK(true);
GRANT SELECT ON app.worker_settings,app.worker_slots,app.worker_heartbeats,app.operational_events,app.model_usage TO internship_operator;
GRANT UPDATE(paused,min_concurrency,target_concurrency,max_concurrency,backlog_per_slot,cooldown_seconds,lease_seconds,daily_token_budget,updated_at)
  ON app.worker_settings TO internship_operator;
DO $operator$
DECLARE name text;
BEGIN
  FOREACH name IN ARRAY ARRAY['worker_settings','worker_slots','worker_heartbeats','operational_events','model_usage'] LOOP
    EXECUTE format('CREATE POLICY operator_management ON app.%I TO internship_operator USING(true) WITH CHECK(true)',name);
  END LOOP;
END
$operator$;

COMMENT ON TABLE app.worker_settings IS 'Database controls only. Python controller and Render deployment are separate backend work.';
COMMENT ON TABLE app.worker_slots IS 'Global active job slots, not machine provisioning or guaranteed provider throughput.';
