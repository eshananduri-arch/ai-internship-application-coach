-- Keep approvals tied to a ready, current draft; serialize competing decisions.
CREATE FUNCTION app.guard_approval_decision() RETURNS trigger
LANGUAGE plpgsql SET search_path = '' AS $decision$
DECLARE draft app.analyses%ROWTYPE;
BEGIN
  SELECT * INTO draft FROM app.analyses WHERE id=NEW.analysis_id AND visitor_id=NEW.visitor_id FOR UPDATE;
  IF NOT FOUND OR draft.status <> 'ready' OR draft.draft_version <> NEW.draft_version THEN
    RAISE EXCEPTION 'The current ready draft must be reviewed before deciding' USING ERRCODE='23514';
  END IF;
  IF NEW.decision='approve' AND (NOT draft.approval_allowed OR NOT NEW.human_confirmed) THEN
    RAISE EXCEPTION 'This draft is not eligible for approval' USING ERRCODE='23514';
  END IF;
  NEW.final_letter := app.normalize_letter(NEW.final_letter);
  RETURN NEW;
END
$decision$;
CREATE TRIGGER current_draft_decision BEFORE INSERT ON app.approval_decisions
  FOR EACH ROW EXECUTE FUNCTION app.guard_approval_decision();
REVOKE ALL ON FUNCTION app.guard_approval_decision() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.guard_approval_decision() TO internship_api;

CREATE FUNCTION app.guard_application_snapshot() RETURNS trigger
LANGUAGE plpgsql SET search_path = '' AS $snapshot$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM app.analyses WHERE id=NEW.analysis_id AND visitor_id=NEW.visitor_id
      AND role_snapshot=NEW.role_snapshot) THEN
    RAISE EXCEPTION 'Application role snapshot must match the reviewed analysis' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END
$snapshot$;
CREATE TRIGGER application_snapshot_guard BEFORE INSERT ON app.applications
  FOR EACH ROW EXECUTE FUNCTION app.guard_application_snapshot();
REVOKE ALL ON FUNCTION app.guard_application_snapshot() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.guard_application_snapshot() TO internship_api;

CREATE INDEX analysis_jobs_analysis_owner_idx ON app.analysis_jobs(analysis_id,visitor_id);
CREATE INDEX applications_analysis_owner_idx ON app.applications(analysis_id,visitor_id);
CREATE INDEX approval_decisions_analysis_owner_idx ON app.approval_decisions(analysis_id,visitor_id);
DROP INDEX app.idempotency_application_idx;
CREATE INDEX idempotency_application_owner_idx ON app.idempotency_requests(application_id,visitor_id);
ALTER POLICY companies_read ON public.companies TO internship_api,internship_worker;
ALTER POLICY roles_read ON public.internship_roles TO internship_api,internship_worker;

REVOKE INSERT ON app.analysis_jobs FROM internship_api;
GRANT INSERT(id,analysis_id,visitor_id) ON app.analysis_jobs TO internship_api;
-- Future app functions must be explicitly granted, rather than executable by PUBLIC.
ALTER DEFAULT PRIVILEGES IN SCHEMA app REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
