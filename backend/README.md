# Firstrole backend version 1

Python FastAPI API plus a separately running durable worker, included in the repository's version 1.0.0 development checkpoint. The local backend connects to Supabase and the published n8n Orchestrator. Hosting on Render is still pending. See [current integration results](../docs/INTEGRATION_STATUS.md).

## Current verification and connection status

- The API runs locally at **http://127.0.0.1:8010** and serves the existing frontend from the same origin.
- **32 Python tests pass**, including the two opt-in real-database HTTP tests for approval, rejection, downloads and cross-visitor isolation.
- **49 live Supabase SQL checks pass**: the 34 database baseline checks plus 15 queue/runtime checks. These test the database through the administrative connector, not through this Python API.
- DOCX and PDF synthetic exports were rendered and visually inspected. Body paragraphs are justified; the greeting and signature are left aligned. TXT preserves the exact approved text.
- All **46 frontend checks** pass with mocked API responses. A local secret scan found no generated session, encryption or administrator secret in Git-visible files.
- Following user approval on 1 November 2026, separate API, worker and operator logins were created with their existing restricted permission groups. The three connection strings are configured only in the ignored local `.env` file. No administrator or RLS-bypass account is used by the app.
- The production n8n webhook is connected and readiness is HTTP 200 locally. A live Microsoft DOCX upload completed generation, approval and exact TXT/DOCX/PDF downloads. Broader runtime results and the remaining PDF test issue are recorded in the integration report. There is no synthetic generation fallback.

## Start locally

From this directory in PowerShell:

```powershell
python -m venv .venv
.venv/Scripts/python.exe -m pip install -r requirements.txt
.venv/Scripts/python.exe scripts/create_local_config.py
.venv/Scripts/python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8010 --no-access-log
```

`create_local_config.py` generates session, encryption and administrator secrets only when `.env` does not exist. It does not create database users or overwrite existing keys. For port 8010, set `APP_ORIGIN=http://127.0.0.1:8010` in that file. Do not serve a mismatched origin or disable CSRF checks.

In another terminal, after configuring suitable existing worker/operator credentials and n8n:

```powershell
.venv/Scripts/python.exe -m app.worker
```

`/health/live` reports process health. `/health/ready` separately reports database, session/encryption configuration and coaching readiness. A live process with `ready: false` is not an integrated working deployment.

## Configuration

Copy settings from `.env.example`; keep actual values in the ignored `.env` file. Never commit or paste secrets into chat. Existing Supabase session-pooler host: `aws-0-ap-south-1.pooler.supabase.com`, port `5432`, database `postgres`. Pooler usernames use `<actual_login>.eztcigkqrhuyeyfgpaor`. The supplied `postgres` connection is an administrator connection; the API intentionally rejects administrator/RLS-bypass roles during readiness checks.

Use existing credentials with the permission groups defined in `../supabase/README.md`: `internship_api`, `internship_worker` and `internship_operator`. These groups are NOLOGIN roles, not standalone credentials. This implementation does not automatically provision login accounts. Database TLS verifies both the certificate chain and hostname. Set `DB_SSLROOTCERT=certs/supabase-root-2021.crt` for the Supabase pooler; relative paths resolve from backend/. All four API/worker/operator pools use this public CA. When unset, the certifi trust bundle is used. Missing configured certificate files fail validation before connection.

Set `N8N_WEBHOOK_URL` to the authenticated production webhook and `N8N_WEBHOOK_TOKEN` to its server-only bearer secret. Plain HTTP is allowed only for localhost in development. Redirects are not followed. Set `N8N_IDEMPOTENT=true` only after the actual workflow implements request deduplication; otherwise uncertain timeouts are not automatically retried.

Keep `RESUME_ENCRYPTION_KEY` stable and back it up securely. Original bytes and extracted text use authenticated Fernet encryption, stored as binary tokens in BYTEA to avoid Base64 storage overhead. Never replace the key to troubleshoot a connection. Key rotation/multiple historical key versions are not implemented; the worker refuses a mismatched version. Database field encryption is limited to resumes; approved letters are private database text protected by access controls.

## Processing and dynamic threads

1. The API validates one real PDF/DOCX, limits total request bytes before multipart parsing, encrypts the upload and commits resume + analysis + job + idempotency record in one PostgreSQL transaction.
2. The existing trigger atomically sends a message containing only the job ID to Supabase Queues/pgmq. The API responds HTTP 202; generation stays outside the web request.
3. A separate Python worker reads the queue and claims a database-backed global slot. It performs document extraction in a subprocess with a timeout; synchronous I/O runs in a bounded thread executor.
4. Default generation capacity is 1, increasing to 2 when at least 3 jobs are waiting and the configured cooldown permits. Database limits apply across worker processes, not independently per server. Provider throttles and the daily token budget take precedence.
5. When the target changes, the old executor drains and a correctly sized one handles new tasks. With no active work, the executor is shut down after 10 seconds. No generation threads stay active just to wait for a user.
6. Heartbeats extend both database leases and queue visibility. Stale tokens cannot overwrite replacement attempts. Retryable throttles back off, uncertain remote requests retain a conservative token reservation, and exhausted jobs become explicit failures.
7. Completion, actual usage accounting, queue acknowledgement and saving the result share a short transaction. No database connection is held during extraction or an n8n network call.

The global default maximum is 2. `MAX_WORKER_CONCURRENCY` provides a separate deployment ceiling. Raising it requires load/quota checks; creating many threads will not make one model call faster. The worker process keeps an idle polling loop with backoff; this does not implement Render instance scale-to-zero or guarantee lower fixed hosting costs. A reliable external wakeup mechanism and billed-cost comparison remain deployment work.

Before dispatch, the database reserves a conservative **12,000-token attempt budget**. Validated reported input/output usage reconciles that reservation on completion. Unknown provider spending stays reserved until the UTC daily boundary or deliberate operator reconciliation. n8n must actually honor the supplied budget and report aggregate usage across its model calls. These reservations are an admission safeguard, not an authoritative provider invoice or a substitute for provider-side quotas.

## API and privacy

The existing frontend contract is implemented under `/api`: session, companies, roles, create/status/recent analyses, approve/reject and approved downloads. Every private route checks the opaque HttpOnly cookie. POST requests require the bound CSRF token and exact configured Origin. No user login page is introduced. Each transaction uses a server-derived visitor ID; browser IDs alone do not authorize access.

Uploads are limited to 5 MB. DOCX archives are checked for traversal, duplicate paths, suspicious expansion, macros and unsafe XML. Extraction runs in a child process with a 10-second timeout; Linux adds memory/CPU limits. Windows deployment still needs an OS/container memory limit. PDFs must be unencrypted, text-based and at most 20 pages. Scanned PDFs need a future OCR path. Extracted text is bounded to 50,000 characters. No original document bytes are sent to n8n.

The API supports exact-text, version-checked approval and rejection. Concurrent decisions lock the analysis and use database uniqueness constraints. Reusing a key with the same payload returns the same receipt; a different payload conflicts. Only explicit approval creates an immutable application. Exports read that saved text, never regenerate a letter or send mail. Current validation cannot prove every resume claim is true; factual quality also depends on the real coaching workflow and human review.

Persistent per-IP/session request limits use HMAC identifiers, not raw IPs. Forwarded client headers are ignored by the application itself. The trusted proxy/forwarding configuration must be tested on Cloudflare/Render to avoid treating all visitors as one proxy IP or trusting forged addresses. Rate-limit table cleanup, session expiry cleanup, retention and an explicit owner deletion/recovery UI remain deployment/product work. No automatic approved-record deletion was enabled.

The production frontend still needs the previously planned replacement of its labelled development catalog fallback and a deliberate recent-record UI. Serving it through this backend uses real catalog endpoints once configured, but the local demo fallback is retained for current offline testing. No letter is displayed on the initial page.

## Protected management

`GET /api/operations` returns aggregate queue state, worker counts, capacity settings and token accounting. `PATCH /api/operations/settings` accepts `paused`, `auto_manage`, `target_concurrency`, `max_concurrency` and `daily_token_budget`, within the deployment ceiling. An explicit target change disables automatic management unless `auto_manage` is supplied.

These endpoints require `Authorization: Bearer <ADMIN_TOKEN>` and the separate operator database credential. The public visitor cookie does not grant operations access. No custom admin dashboard is included. Do not put the administrator token in frontend code. Existing database records retain updated timestamps; a complete administrator identity/audit interface is future work.

## n8n response contract

See [`N8N_CONTRACT.md`](N8N_CONTRACT.md). The adapter rejects mismatched IDs, incomplete JSON, unverified selected-role evidence, a word count that does not match the exact returned letter, placeholders, missing usage and a critic that has not approved the result. Runtime tool evidence must be constructed from actual node outputs in the trusted workflow, never copied from a model's self-report. The real adapter has been tested against the published Orchestrator. See the integration report for which paths passed and which remain unresolved. It preserves allowlisted pipeline failure codes without retaining provider messages or private response payloads.

## Tests

```powershell
.venv/Scripts/python.exe -m pytest -q
.venv/Scripts/python.exe -m pip check
```

The default Python suite uses synthetic local documents and a mocked HTTP transport for contract testing. `scripts/check_connections.py` verifies the actual configured API, worker and operator logins without printing passwords or private records. Those responses are test-only; the running application cannot use them. Real PostgreSQL HTTP tests are explicitly opt-in:

```powershell
$env:FIRSTROLE_INTEGRATION='1'
.venv/Scripts/python.exe -m pytest -m integration -q
```

Use only the development database with a restricted existing API login. The HTTP tests create their own synthetic visitors/records and remove those visitors afterward; they do not enqueue AI work. The database SQL suites in `../supabase/tests/` roll back all fixtures and queue messages. No SQLite substitute is used. Cross-process Python worker load, crash recovery against live n8n and all-15-role AI latency tests remain unrun until the required runtime access and workflow exist.

Security advisors currently show one informational RLS-without-policy notice for the internal rate-limit table, which intentionally denies all direct application access and is accessed through a restricted internal function. [Explanation](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy). Performance notices are unused indexes on a fresh database; [guidance](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).

## Files

```text
backend/
  app/
    config.py        validated environment configuration
    db.py            bounded PostgreSQL connection pools and owner context
    security.py      private cookies, CSRF, hashing and resume encryption
    middleware.py    streaming request-size and upload-time limits
    main.py          HTTP routes and same-origin frontend serving
    repository.py    catalog, queued intake, private records and decisions
    documents.py     upload inspection and child-process orchestration
    extract_child.py bounded document text extraction
    coaching.py      authenticated n8n adapter and result validation
    exports.py       genuine DOCX, PDF and TXT exports
    worker.py        queue consumer, threads, controller and lease heartbeat
  scripts/create_local_config.py
  tests/test_backend.py
  tests/test_postgres_integration.py
  .env.example
  requirements.txt   exact resolved dependency pins
  pyproject.toml
```

There is no Alembic schema history: use the versioned Supabase migrations already applied. Hosting deployment, backup/restore testing, recovery flows and public launch are not part of this local backend milestone.
