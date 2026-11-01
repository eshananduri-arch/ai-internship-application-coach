# Database version 1

The development database is provisioned in **Supabase Mumbai (`ap-south-1`)**.
Project: `internship-coach-dev`, reference `eztcigkqrhuyeyfgpaor`.
[Open the project](https://supabase.com/dashboard/project/eztcigkqrhuyeyfgpaor).

This database definition is included in version 1.0.0. [`project.json`](project.json) identifies the hosted development project; [`REPOSITORY_LINK.md`](REPOSITORY_LINK.md) distinguishes source versioning from the pending authenticated CLI/dashboard GitHub link. GitHub repository access does not grant database access. No automatic deployment is enabled.

Eight versioned application-schema migrations are included here. Hosted history additionally contains environment-specific login provisioning operations; their password hashes and secret values are deliberately excluded from source. Do not configure unattended migration deployment without reconciling that environment-specific history. Treat this directory as the single schema history. Do not manage these same tables with a separate Alembic history or reapply the older `workflows/mcp/prepare_knowledge_database.sql` bootstrap. New changes require a new migration.

**Backend update:** an eighth migration, `backend_runtime_management`, adds persistent rate limits, token reservations, usage settlement, retry/reconciliation helpers and operations aggregates. Python implementation is now in `../backend/`. The user approved runtime logins on 1 November 2026; the local API, worker and operator are now connected with separate restricted accounts. The additional live SQL suite passed 15 checks, alongside the 34 baseline checks.

## What exists

| Area | Tables / functions | Purpose |
| --- | --- | --- |
| Shared catalog | `public.companies`, `internship_roles` | Five companies and 15 fictional educational roles, matching the frontend catalog |
| Retrieval sources | `public.role_documents`, `internship_role_chunks` | Five versioned source documents; pgvector schema compatible with the exported MCP tool |
| Anonymous visitors | `app.visitors`, `sessions` | Server-managed ownership, hashed session and CSRF secrets, expiry |
| Resume intake | `app.resumes` | Encrypted original/text columns, size/type metadata and extraction state |
| Generation | `app.analyses` | Role snapshot, draft version, letter and review/tool evidence |
| Human decisions | `app.approval_decisions`, `applications` | Current-draft checks, explicit confirmation, exact approved text, immutable final records |
| Duplicate protection | `app.idempotency_requests` | Session-scoped request keys and payload hashes |
| Durable work | `app.analysis_jobs`, `pgmq` queue | Transactional enqueue with job ID only; processing state and retry limits |
| Worker management | `worker_settings`, `worker_slots`, `worker_heartbeats` | Global capacity controls, lease tokens, pause/drain foundations |
| Operations | `operational_events`, `model_usage` | Event codes and token counts, without resume/letter payload columns |

The role knowledge index has been built by the live Knowledge Loader and used successfully through MCP. Synthetic integration visitors and private records are removed after checks. Real private resumes and approved letters are never versioned in this repository. See the current integration report for runtime status.

## Access boundaries

All application tables have row-level security enabled. `anon` and `authenticated` have no access to the private `app` schema or queue. The browser will use Python `/api`, not direct Supabase access.

The following are **NOLOGIN permission roles**, not ready-to-use database credentials:

- `internship_api`: session management, catalog reads, and visitor-scoped application records.
- `internship_worker`: private analysis/resume processing, queue helpers and telemetry; no approved-application writes.
- `internship_mcp_reader`: role chunks only; cannot read resumes.
- `internship_knowledge_writer`: shared catalog/document/chunk indexing only.
- `internship_operator`: worker controls and operational metrics; no resume or letter reads.

During backend/n8n integration, provision separate secure login credentials and grant only the matching permission role. Never give the browser a database password, migration administrator, worker login or Supabase service-role secret. Connection strings and encryption keys belong in local ignored environment files and deployment secrets, not Git.

The API must establish the visitor from a verified high-entropy HttpOnly cookie. Inside each database transaction use parameterized `set_config('app.visitor_id', visitor_id, true)`. This value comes from the server session lookup, never from request JSON. Transaction-local context prevents pooled connection leakage. Session/visitor management is trusted API access; RLS does not replace cookie authentication, CSRF, origin checks or route authorization.

Resume columns require application-encrypted bytes. SQL does not perform or validate authenticated encryption. Python must encrypt before persistence and keep the key outside PostgreSQL; test fixture byte strings are not an encryption implementation. Approved letters remain private database text protected by server permissions/RLS; broader field encryption can be introduced separately.

## Backend transaction contracts

1. Intake: validate the actual upload, resolve a catalog role, encrypt the file, and insert resume + analysis + analysis job + idempotency record in one transaction. The job trigger sends its ID to pgmq in that transaction. Return HTTP 202 promptly.
2. Worker: read `app.read_analysis_queue()`, load the referenced job, and claim `app.claim_worker_slot(worker_id, job_id)`. No capacity means leave it for redelivery; do not discard it. Ignore/resolve already terminal jobs. Heartbeat the token while processing.
3. Completion: in a short transaction call `app.finish_analysis_job()` with the current worker/token. Only on a true result persist the matching analysis output in that same transaction; roll back everything if saving fails. Never write a result after a false fencing check. The function releases capacity, terminalizes the job and archives its message atomically.
4. Approval: verify the visitor and CSRF, lock the analysis, check the current draft/version and review the submitted exact text. Insert the decision, then insert the application only for approval, copying the original role snapshot. Update analysis status and idempotency response in the same transaction. Reject creates a decision and no application. A unique analysis decision prevents conflicting double decisions.
5. Downloads: authorize the current owner before generating DOCX/PDF/TXT from the immutable application text. The database does not generate files.

The database cannot prove a human clicked a button; the authenticated API must set `human_confirmed` only after explicit user action. Text normalization changes line endings only, retaining content and spacing.

## Queue and dynamic capacity

The default global target is **1** job with a configured maximum of **2**, shared across all worker processes. Sixteen physical slot rows provide an upper schema limit for future approved configuration. A locked singleton settings row serializes claims. Reducing a target drains existing work; it does not terminate it. Pause blocks new claims. Expired leases can be reclaimed with a fresh token; stale tokens cannot complete or heartbeat the replacement lease. Queue visibility is extended with a claim/heartbeat.

The Python worker now runs locally with the dispatcher, lease heartbeats, retry/backoff classification, exhausted-job handling, controller, operational endpoints and usage-budget enforcement. Hosting-level instance scaling and a deployment wakeup strategy remain future work. A controller must archive/terminalize exhausted or cancelled messages. Monitor idempotent redelivery and at-least-once processing; do not claim exactly-once model calls. Initial job maximum attempts is 3, bounded to 5.

Reducing concurrency does not by itself reduce a fixed Render service bill. Actual machine scaling, provider quotas and costs must be configured during deployment. There is no sub-10-second latency guarantee from these database changes.

## Verification

`tests/database_v1.sql` passed **34 checks on the live development database** on 2026-10-31. It uses synthetic fixtures inside a rolled-back transaction. It tests all catalog company/role associations, private access, cross-owner relationships, exact approval/rejection, immutable final records, transactional queue rollback, queue reads, global slot limits, pause, heartbeat, reclaim and stale-token fencing. It is a database integration suite, not a concurrent load or provider latency test.

Run it with the migration administrator, for example `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/database_v1.sql`. Use a secure connection with TLS. It intentionally asserts the pristine development catalog and no embedded chunks; update its indexing expectations after the knowledge-loading phase. It assumes no unrelated jobs are running.

Supabase security advisors returned **no findings**. Performance advisors have only informational unused-index notices on this new database; indexes supporting ownership and queue queries are retained. [Supabase's unused-index guidance](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).

Current schema inventory, migration versions and test results are recorded in `verification.json`. No service passwords or keys are included.

## Remaining integration

The local Python backend and published n8n workflows are connected. The frontend can use them through the same-origin API at http://127.0.0.1:8010/. See `../docs/INTEGRATION_STATUS.md` for exact tested paths and limitations. Configure production backups/restore testing, retention, file encryption, rate limits and provider secrets before production use. No automatic deletion policy has been activated for approved applications. Anonymous visitors may lose access if they clear their cookie or it expires; a recovery flow would require a separate product decision.

To inspect private tables in the Supabase dashboard Table Editor, select the **app** schema. Shared catalog tables are under **public**. Dashboard access is administrative and must not be confused with the app's visitor access.
