-- Private records are not exposed through the Supabase Data API.
CREATE TABLE app.visitors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visitor_id uuid NOT NULL REFERENCES app.visitors(id) ON DELETE CASCADE,
  secret_hash text NOT NULL UNIQUE CHECK (secret_hash ~ '^[0-9a-f]{64}$'),
  csrf_hash text NOT NULL CHECK (csrf_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL CHECK (expires_at > created_at),
  revoked_at timestamptz
);
CREATE INDEX sessions_visitor_idx ON app.sessions(visitor_id);
CREATE INDEX sessions_expiry_idx ON app.sessions(expires_at);

CREATE TABLE app.resumes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visitor_id uuid NOT NULL REFERENCES app.visitors(id) ON DELETE CASCADE,
  file_name text NOT NULL CHECK (char_length(file_name) BETWEEN 1 AND 255),
  file_type text NOT NULL CHECK (file_type IN ('pdf','docx')),
  byte_size integer NOT NULL CHECK (byte_size BETWEEN 1 AND 5242880),
  file_sha256 text NOT NULL CHECK (file_sha256 ~ '^[0-9a-f]{64}$'),
  encrypted_original bytea NOT NULL CHECK (octet_length(encrypted_original) BETWEEN 1 AND 6291456),
  encrypted_text bytea,
  encryption_key_version text NOT NULL CHECK (char_length(encryption_key_version) BETWEEN 1 AND 100),
  extraction_status text NOT NULL DEFAULT 'pending' CHECK (extraction_status IN ('pending','ready','failed')),
  character_count integer CHECK (character_count >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, visitor_id)
);
CREATE INDEX resumes_visitor_idx ON app.resumes(visitor_id,created_at DESC);

CREATE TABLE app.analyses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visitor_id uuid NOT NULL REFERENCES app.visitors(id) ON DELETE CASCADE,
  resume_id uuid NOT NULL,
  request_id text NOT NULL CHECK (char_length(request_id) BETWEEN 1 AND 100),
  company_id text NOT NULL,
  role_id text NOT NULL,
  role_snapshot jsonb NOT NULL CHECK (jsonb_typeof(role_snapshot) = 'object'),
  candidate_name text NOT NULL CHECK (char_length(candidate_name) BETWEEN 2 AND 100),
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued','processing','ready','failed','blocked','approved','rejected','cancelled')),
  stage text NOT NULL DEFAULT 'queued' CHECK (char_length(stage) <= 180),
  draft_version integer NOT NULL DEFAULT 0 CHECK (draft_version >= 0),
  final_letter text CHECK (char_length(final_letter) BETWEEN 1 AND 20000),
  final_letter_sha256 text GENERATED ALWAYS AS (app.letter_sha256(final_letter)) STORED,
  match_report jsonb,
  deadline_info jsonb,
  critic_review jsonb,
  tool_evidence jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(tool_evidence) = 'array'),
  approval_allowed boolean NOT NULL DEFAULT false,
  failure_code text CHECK (char_length(failure_code) <= 100),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, visitor_id),
  UNIQUE (visitor_id, request_id),
  FOREIGN KEY (resume_id, visitor_id) REFERENCES app.resumes(id,visitor_id) ON DELETE CASCADE,
  FOREIGN KEY (role_id, company_id) REFERENCES public.internship_roles(role_id,company_id),
  CHECK (status NOT IN ('ready','approved','rejected') OR (draft_version >= 1 AND final_letter IS NOT NULL))
);
CREATE INDEX analyses_resume_owner_idx ON app.analyses(resume_id,visitor_id);
CREATE INDEX analyses_role_company_idx ON app.analyses(role_id,company_id);
CREATE INDEX analyses_owner_created_idx ON app.analyses(visitor_id,created_at DESC);
CREATE INDEX analyses_status_idx ON app.analyses(status,created_at);

CREATE TABLE app.approval_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  analysis_id uuid NOT NULL UNIQUE,
  visitor_id uuid NOT NULL,
  decision text NOT NULL CHECK (decision IN ('approve','reject')),
  human_confirmed boolean NOT NULL DEFAULT false,
  draft_version integer NOT NULL CHECK (draft_version >= 1),
  final_letter text NOT NULL CHECK (char_length(final_letter) BETWEEN 1 AND 20000),
  final_letter_sha256 text GENERATED ALWAYS AS (app.letter_sha256(final_letter)) STORED,
  idempotency_key text NOT NULL CHECK (char_length(idempotency_key) BETWEEN 1 AND 100),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (analysis_id,visitor_id) REFERENCES app.analyses(id,visitor_id) ON DELETE CASCADE,
  UNIQUE (visitor_id,idempotency_key),
  CHECK (decision <> 'approve' OR human_confirmed)
);
CREATE INDEX approval_decisions_owner_idx ON app.approval_decisions(visitor_id);

CREATE TABLE app.applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visitor_id uuid NOT NULL,
  analysis_id uuid NOT NULL UNIQUE,
  decision_id uuid NOT NULL UNIQUE REFERENCES app.approval_decisions(id) ON DELETE CASCADE,
  role_snapshot jsonb NOT NULL CHECK (jsonb_typeof(role_snapshot) = 'object'),
  final_letter text NOT NULL CHECK (char_length(final_letter) BETWEEN 80 AND 20000),
  final_letter_sha256 text GENERATED ALWAYS AS (app.letter_sha256(final_letter)) STORED,
  approved_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id,visitor_id),
  FOREIGN KEY (analysis_id,visitor_id) REFERENCES app.analyses(id,visitor_id) ON DELETE CASCADE
);
CREATE INDEX applications_owner_idx ON app.applications(visitor_id,approved_at DESC);

CREATE TABLE app.idempotency_requests (
  visitor_id uuid NOT NULL REFERENCES app.visitors(id) ON DELETE CASCADE,
  route text NOT NULL,
  request_key text NOT NULL CHECK (char_length(request_key) BETWEEN 1 AND 100),
  payload_sha256 text NOT NULL CHECK (payload_sha256 ~ '^[0-9a-f]{64}$'),
  analysis_id uuid,
  application_id uuid,
  http_status integer CHECK (http_status BETWEEN 100 AND 599),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (visitor_id,route,request_key),
  FOREIGN KEY (analysis_id,visitor_id) REFERENCES app.analyses(id,visitor_id) ON DELETE CASCADE,
  FOREIGN KEY (application_id,visitor_id) REFERENCES app.applications(id,visitor_id) ON DELETE CASCADE
);
CREATE INDEX idempotency_analysis_idx ON app.idempotency_requests(analysis_id,visitor_id);
CREATE INDEX idempotency_application_idx ON app.idempotency_requests(application_id);

CREATE FUNCTION app.guard_approved_application() RETURNS trigger
LANGUAGE plpgsql SET search_path = '' AS $guard$
DECLARE decision_record app.approval_decisions%ROWTYPE;
BEGIN
  SELECT * INTO decision_record FROM app.approval_decisions WHERE id = NEW.decision_id;
  IF NOT FOUND OR decision_record.decision <> 'approve' OR NOT decision_record.human_confirmed
     OR decision_record.analysis_id <> NEW.analysis_id OR decision_record.visitor_id <> NEW.visitor_id
     OR app.normalize_letter(decision_record.final_letter) <> app.normalize_letter(NEW.final_letter) THEN
    RAISE EXCEPTION 'An application requires a matching explicit approval of its exact text' USING ERRCODE='23514';
  END IF;
  NEW.final_letter := app.normalize_letter(NEW.final_letter);
  RETURN NEW;
END
$guard$;
CREATE TRIGGER approved_application_guard BEFORE INSERT ON app.applications
  FOR EACH ROW EXECUTE FUNCTION app.guard_approved_application();

CREATE FUNCTION app.prevent_final_record_update() RETURNS trigger
LANGUAGE plpgsql SET search_path = '' AS $immutable$
BEGIN
  RAISE EXCEPTION 'Final approval records are immutable; create a new analysis for a new version' USING ERRCODE='23514';
END
$immutable$;
CREATE TRIGGER immutable_approved_text BEFORE UPDATE ON app.applications
  FOR EACH ROW EXECUTE FUNCTION app.prevent_final_record_update();
CREATE TRIGGER immutable_decision BEFORE UPDATE ON app.approval_decisions
  FOR EACH ROW EXECUTE FUNCTION app.prevent_final_record_update();

-- No public grants and default-deny RLS, even if a private schema is exposed accidentally.
DO $security$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['visitors','sessions','resumes','analyses','approval_decisions','applications','idempotency_requests'] LOOP
    EXECUTE format('ALTER TABLE app.%I ENABLE ROW LEVEL SECURITY',table_name);
    EXECUTE format('REVOKE ALL ON app.%I FROM PUBLIC, anon, authenticated',table_name);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON app.%I TO internship_api',table_name);
    IF table_name IN ('visitors','sessions') THEN
      EXECUTE format('CREATE POLICY trusted_session_management ON app.%I TO internship_api USING (true) WITH CHECK (true)',table_name);
    ELSE
      EXECUTE format('CREATE POLICY visitor_ownership ON app.%I TO internship_api USING (visitor_id = app.current_visitor_id()) WITH CHECK (visitor_id = app.current_visitor_id())',table_name);
    END IF;
  END LOOP;
END
$security$;

GRANT SELECT ON app.resumes, app.analyses TO internship_worker;
GRANT UPDATE (encrypted_text,extraction_status,character_count) ON app.resumes TO internship_worker;
GRANT UPDATE (status,stage,draft_version,final_letter,match_report,deadline_info,critic_review,tool_evidence,approval_allowed,failure_code,updated_at)
  ON app.analyses TO internship_worker;
CREATE POLICY trusted_worker ON app.resumes TO internship_worker USING (true) WITH CHECK (true);
CREATE POLICY trusted_worker ON app.analyses TO internship_worker USING (true) WITH CHECK (true);
REVOKE ALL ON FUNCTION app.guard_approved_application(),app.prevent_final_record_update() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.guard_approved_application() TO internship_api;

COMMENT ON SCHEMA app IS 'Private Python-owned records. Not an anonymous Supabase Data API schema.';
COMMENT ON COLUMN app.resumes.encrypted_original IS 'Application-encrypted bytes; encryption keys never stored in this database.';
COMMENT ON COLUMN app.sessions.secret_hash IS 'SHA-256 of a high-entropy session secret. Never store the raw cookie.';
