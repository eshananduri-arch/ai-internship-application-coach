# Integration status, 1 November 2026

## Connected locally

- FastAPI: http://127.0.0.1:8010/ ; readiness reports database, private sessions and coaching configured. This is local development, not a deployed public service.
- API, queue worker and management services use three separate Supabase session-pooler login accounts. Each inherits only internship_api, internship_worker or internship_operator. All use verified TLS with the public Supabase CA; none is administrator or RLS bypass. Passwords, connection URLs, session/encryption secrets and webhook token remain in ignored local environment files.
- The published development n8n MCP endpoint is `/mcp/final-career-tools`; the Orchestrator production webhook is `/webhook/final-internship-coach` on zeeshan1786.app.n8n.cloud. Backend requests use server-only Bearer authentication and an Idempotency-Key. Clicking Execute on the webhook canvas waits for a request; it does not synthesize one.
- Queue processing happens outside HTTP intake. A database-backed global lease limits work; the controller starts/drains bounded thread executors with a development ceiling of two concurrent jobs. This does not implement hosting instance scale-to-zero.

## Verification evidence

| Check | Result | Scope |
| --- | --- | --- |
| Backend pytest with FIRSTROLE_INTEGRATION=1 | 32 passed | Includes real Supabase approval/rejection, exact downloads and cross-owner isolation |
| Python dependency consistency | Passed | pip check |
| Frontend browser suite | 46 passed | Mocked API responses, not live provider generation |
| Final workflow checks | Passed | Six imports, 26 Code scripts, 12 MCP response cases |
| Three runtime database logins | Passed | Verified SSL, correct inherited groups, no superuser or RLS bypass |
| Published Orchestrator synthetic Microsoft request | Passed, 11.23 seconds | 166-word letter passed actual Python response validation |
| Microsoft DOCX through HTTP API and queue | Passed, 20.66 seconds | Fresh upload, private session, duplicate-submit idempotency, live n8n, encrypted storage, approval, identical TXT/DOCX/PDF downloads, other visitor denied |
| Direct Amazon raw-text and extracted-PDF webhook diagnostics | Passed, 9.50 and 10.06 seconds | Role search, generation, critic, exact letter word-count evidence |
| Amazon PDF through full queue | Investigation required | Some runs returned n8n HTTP 502; no application was approved or saved. Keep evidence/schema checks enabled. No automatic uncertain request replay was added. |

Live test uploads used synthetic resumes and separate temporary visitors; their private records were removed afterward. These small tests do not establish all-role AI quality, concurrent-load performance, a sub-10-second guarantee, or production readiness. Provider/model output may fail validation; the app must report that safely.

## Running and checking

From backend/:

```powershell
.venv/Scripts/python.exe scripts/check_connections.py
.venv/Scripts/python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8010 --no-access-log
# Separate terminal:
.venv/Scripts/python.exe -m app.worker
```

The .env.example lists required settings. Keep the current encryption/session keys stable. New maintainers must obtain their own secrets and suitable restricted database access; a public source repository never contains a shared database password. Configure environment secrets separately on Render.

## Remaining work

Diagnose the intermittent queue-driven Amazon PDF failure; extend live checks to all 15 roles and concurrent clients; configure Cloudflare/Render routing and cookie behavior; remove the development frontend catalog fallback for public launch; add retention/recovery and backup checks; reconcile environment-specific authentication migration history before automated database deployment. No Cloudflare/Render publication or automatic GitHub-to-n8n deployment is enabled.

The current schema and educational role sources are versioned under supabase/ and role_documents/. Runtime-specific login provisioning and private n8n credential bindings are deliberately separate from those reusable files. The original v1.0.0 tag is preserved as historical checkpoint.
