# Backend implementation plan

**31 October update:** Supabase database version 1 now exists in Mumbai; see [`supabase/README.md`](supabase/README.md) for the actual tables, restricted roles, queue/lease functions and transaction contracts. Implement the backend against that schema rather than recreating proposed tables below. The API, worker/controller and deployment remain pending.

**Implementation update:** the API and worker/controller code are included in the version 1.0.0 development checkpoint; see [`backend/README.md`](backend/README.md) and its verification report. Existing runtime database credentials, live n8n integration and deployment remain pending. The schema continues to use Supabase migrations, not the historical Alembic proposal below.

Planning baseline: 30 October 2026. This document proposes the implementation; no backend service or PostgreSQL database has been created or connected yet.

## Product flow

1. Open the existing frontend without a login page. The backend establishes a private anonymous session.
2. Upload one PDF or DOCX, choose a company and its role, and provide the signature name on the same page.
3. The API validates the submission, stores its records in PostgreSQL, queues processing and promptly returns an analysis ID.
4. A Python worker extracts the uploaded resume's text and calls the n8n coaching workflow. The frontend polls status and shows the real result when ready.
5. The visitor reads or edits the letter, then explicitly approves or rejects it.
6. Approval saves the exact approved text as an immutable application record. Download exports that text as DOCX, PDF or TXT. Rejection cannot create an approved application or unlock an export.

There is no automatic application submission or email sending. No example letter is shown before processing. Production must never silently substitute synthetic test data or a previous upload's text.

## Architecture

```text
Browser: existing frontend
        | HTTPS, same-origin /api requests and private session cookie
        v
Python FastAPI web service ---- PostgreSQL
        |                        sessions, catalog, resumes,
        |                        analyses, jobs, decisions, applications
        |
Python worker ---------------- PostgreSQL-backed job queue
        |
        | authenticated, server-to-server production webhook
        v
n8n coaching workflow -------- Gemini + MCP tools + role retrieval
```

The web process and worker use the same backend package and database, deployed as separate processes. PostgreSQL is the source of truth for product records. Browser memory holds only the currently displayed state. n8n processes inputs and returns results; it does not independently save applications into its old tracker table.

Use FastAPI and Pydantic for the HTTP boundary, SQLAlchemy with psycopg for PostgreSQL access, and Alembic for schema migrations. Resolve and lock compatible dependency versions when implementation starts. Use python-docx for DOCX extraction/export, pypdf for text PDFs, and ReportLab for PDF exports. Scanned PDFs need OCR; initially return a clear unsupported-document error rather than generating from missing text.

Keep generation outside the web process. The worker claims jobs using a short transaction and `FOR UPDATE SKIP LOCKED`, then releases that transaction before any file extraction or network call. Jobs have a lease, heartbeat, attempt limit and reclaim procedure so a process restart cannot silently lose a submission. PostgreSQL documents SKIP LOCKED as useful for queue-like tables. FastAPI also distinguishes simple background tasks from work better handled outside the request process. [PostgreSQL SELECT](https://www.postgresql.org/docs/current/sql-select.html), [FastAPI background tasks](https://fastapi.tiangolo.com/tutorial/background-tasks/).

## Backend folder

```text
backend/
  pyproject.toml
  dependency lock file
  .env.example
  alembic.ini
  migrations/
  app/
    main.py                    # API setup, static frontend, health checks
    config.py                  # Environment and validated settings
    db.py                      # Connection/session lifecycle
    models/                    # PostgreSQL tables and constraints
    schemas/                   # Request and response validation
    api/
      dependencies.py          # Visitor ownership and CSRF checks
      sessions.py
      catalog.py
      analyses.py
      applications.py
    services/
      sessions.py
      uploads.py               # File limits, signature/archive inspection
      extraction.py            # Current upload -> text
      jobs.py                  # Durable job lifecycle and leases
      coaching.py              # n8n adapter and strict output validation
      approval.py              # Transactional exact-text decisions
      exports.py               # Genuine DOCX/PDF/TXT
      retention.py             # Explicit cleanup and deletion rules
    worker.py
  scripts/
    import_catalog.py          # Intentional one-time import, never startup fallback
  tests/
    unit/
    integration/
    fixtures/                  # Synthetic documents only
docs/
  deployment.md
workflows/
  career_coach_api.json        # Sanitized export, no credentials or real resumes
```

No backend files are scaffolded by this planning step. Frontend/API field names must remain compatible with `frontend/API_CONTRACT.md` or be changed together.

## PostgreSQL records

| Table | Purpose and main rules |
| --- | --- |
| visitors | Durable anonymous owner ID; no username or password. |
| sessions | Hash of an opaque secret, visitor ID, CSRF binding and expiry. Never store the raw session secret in logs. |
| companies | Company names and active state, read through the API. |
| roles | Company relationship, stable role ID, title, requirements, location, deadline, source and catalog version. |
| resumes | Owner, original filename, actual type, byte count, digest, original document bytes and extracted text. All private. |
| analyses | Owner, resume/role references, authoritative role snapshot, candidate name, processing state, draft version, draft text and review result. |
| analysis_jobs | Analysis ID, queued/running/completed/failed state, attempt count, lease and safe failure code. |
| approval_decisions | Owner, analysis/version, approve or reject, timestamp and exact submitted text hash. |
| applications | Owner, unique analysis ID, decision reference, immutable approved text, approved-text hash and approval time. |
| idempotency_requests | Owner, route, key, request digest and outcome reference; prevent double submissions and double saves. |

Use foreign keys, ownership indexes and unique constraints, including one finalized decision/application per analysis. IDs exposed to browsers must be unguessable; every private query must still check ownership. Store timestamps in UTC.

Production data belongs in PostgreSQL, including the role catalog and resume records. With the present 5 MB upload cap, original documents can be stored in a private BYTEA column; use application-level encryption for document bytes and extracted text, with keys held outside the database. Approved letters and other private content need equivalent storage protection. Database backups and encryption-key backup/rotation are part of deployment, not a browser feature. Export files can be generated on demand from the immutable approved text rather than kept as duplicate files.

Do not automatically import testing resumes or pretend the fictional catalog is verified live recruitment data. Import the agreed catalog explicitly and label its source. Local JSON fallback and mocked API responses stay development/test-only and are removed from the production frontend path once the real catalog API is ready.

Drafts and processing records must be stored before approval so jobs can resume and the visitor can refresh. These records are not approved applications. Only the approval transaction creates an application. Define retention before deployment: proposed seven-day cleanup for abandoned uploads/drafts, with approved applications retained until the visitor deletes them or an explicitly documented retention policy applies. This proposal requires review if resumes need long-term reuse; do not implement silent deletion of approved records.

## No-login access and restoring state

- Issue a long, random session secret in an HttpOnly cookie; use Secure in production and SameSite=Lax. Keep its hash server-side and validate CSRF/Origin on state-changing requests.
- Authorize access by the session's visitor ID, never by a submitted owner field or application ID alone.
- Add an owner-scoped recent analyses/applications endpoint so refresh can restore jobs and approved records from PostgreSQL. This needs a small frontend change; it is not implemented today.
- Separate browsers/devices get separate ownership. Clearing or losing the cookie loses access to the previous anonymous identity, even though records remain in the database. Persistence does not imply cross-device recovery.
- Proposed follow-up: an optional recovery code shown once, with only its hash stored. Do not add login, recovery UI or transfer ownership without agreeing the product flow first.

Test isolation with two completely independent browser sessions, including copied IDs and download URLs. Shared devices using the same browser cookie share the anonymous identity; an explicit clear-session option can start a new identity.

## API implementation order

Keep existing frontend routes:

| Route | Behavior |
| --- | --- |
| GET /api/session | Establish/resume anonymous session and return CSRF token. |
| GET /api/companies | Read company records from PostgreSQL. |
| GET /api/roles?company=... | Read that company's allowed roles. |
| POST /api/analyses | Validate multipart upload, save and queue atomically; return HTTP 202 with analysis ID. |
| GET /api/analyses/{id} | Owner-only current status and complete result when ready. |
| POST /api/analyses/{id}/decision | Owner-only exact-text approval/rejection with version and idempotency checks. |
| GET /api/applications/{id}/download?format=... | Owner-only genuine approved export. |

Add owner-scoped recent-record listing and explicit deletion endpoints during the persistence phase, updating the contract and frontend together. Provide separate liveness/readiness checks, with readiness verifying the database and migrations. No fake success if PostgreSQL is down.

Limit uploads by actual bytes and inspect file signatures; extensions alone are insufficient. Bound DOCX archive expansion, extraction time and text length. Reject empty, password-protected or unreadable documents clearly. Avoid logging private text, raw document contents or session secrets.

## n8n integration

Adapt the chosen working workflow to an authenticated production Webhook entry point and a defined JSON response. Export the workflow into Git without secrets. Existing Form pages and cross-workflow calls are not the web application's API. n8n documents distinct test and published production webhook URLs and supports authentication. [n8n Webhook](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/).

The worker sends `analysis_id`, a stable attempt/request ID, selected company and role ID, role source/version, extracted resume text, candidate name and the current date. It never sends the browser cookie or database credentials. Keep n8n URL and authentication secret in server configuration. Do not accept a browser-supplied webhook URL.

Require a typed result containing the same analysis and role IDs, a complete plain-text final letter, match details and reviewer output. Reject mismatched IDs, truncated JSON, missing letters, placeholders or unsupported claims. Bind tool traces to the analysis and verify assignment-required MCP actions through structured execution evidence rather than a model's assertion that it called a tool. Previously observed MCP validation failures remain unresolved until this adapter is tested against the actual revised workflow.

Keep the assignment's required agents, RAG, tools and human decision. Reduce repeated orchestration calls, retrieve only the selected role, pass compact structured data between agents and bound revision loops. Record time spent in extraction, queueing, n8n/model calls, validation and exports separately.

Target fast execution, but do not promise a fixed ten-second AI completion time. The API acknowledgment should be quick because it returns a queued job; the actual model duration must be measured across all 15 roles. Never replace required agent/tool work with a fake result to meet a timing target.

Use explicit network timeouts, a total generation budget, bounded worker retries and stable request IDs. A timeout is not proof the remote work never happened. Automatically retry only where duplicate execution is harmless or supported by n8n request deduplication. Saving approved applications remains entirely in the Python backend.

## Approval and export correctness

Within one transaction: lock the analysis, verify owner/state/version, validate the submitted edited text, insert the decision, create the application containing that exact text, and commit before returning approved. Retry with the same idempotency key returns the same saved record; another payload under that key returns conflict. A rejected/finalized analysis cannot be approved by racing a second request.

Local checks can count words or flag placeholders, but they cannot prove a letter is factually perfect. Edits that require AI review must be visibly re-reviewed and re-confirmed before approval; never silently rewrite an already approved letter. Return clear validation errors and keep the editable draft available.

Generate DOCX/PDF/TXT from the saved immutable text. Justify body paragraphs, keep salutation/signature left aligned, use restrained typography, and preserve paragraph breaks. Test Unicode names, punctuation, long names and multi-page overflow. On export failure keep the saved approval intact and allow export retry.

## Delivery phases and completion checks

1. **Database and private sessions.** PostgreSQL migrations, configuration, catalog import and anonymous ownership. Verify two visitors cannot read each other's records. No SQLite substitute in integration tests.
2. **Upload and durable processing.** Real PDF/DOCX extraction and PostgreSQL jobs. Verify different resumes produce different stored input; restarting the web service or worker does not lose queued work.
3. **Live n8n connection.** Revised webhook contract and strict output validation. Exercise all 15 roles, record latency and expose actionable failures. Synthetic responses stay test-only.
4. **Approval and exports.** Atomic exact-version saves, rejection, double-click/concurrent decision tests, genuine document downloads and visual inspection of exported layout.
5. **Frontend persistence and deployment.** Restore jobs/records after refresh, replace production catalog fallback, configure one HTTPS origin, provision managed PostgreSQL and the worker, run migrations, and verify backup/restore. Keep secrets out of GitHub.

The first coding milestone should be phase 1: a locally runnable backend connected to PostgreSQL with session, company and role endpoints. That validates the data foundation before adding AI latency and workflow complexity.

## Decisions needed before provisioning, not before planning

- Who will provision PostgreSQL and the deployment account, and how will server credentials be supplied securely?
- Which revised n8n workflow/export will be the authoritative production pipeline? Its current behavior must be inspected before wiring it in.
- Confirm retention and whether optional no-login recovery is needed before public launch.

These do not block preparing backend code, migrations or tests once implementation is approved. Do not create paid services, deploy publicly or push to GitHub as part of this planning request.
