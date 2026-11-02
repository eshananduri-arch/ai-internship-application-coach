# Integration status, updated 2 November 2026

## Deployed API startup recovery, 2 November 2026

The public page returned 200 while `/api/session` returned 502 before a resume was submitted. Direct Render health requests then returned 200 after 32.92 and 36.23 seconds, and the proxied session route recovered to 200. This is consistent with backend startup/wake-up; the service plan/deployment event was not inspected. Render documents that free services sleep after 15 idle minutes and can take about a minute to wake: https://render.com/docs/free .

The frontend now retries only transient session GET failures (network/502/503/504), with exponential waits capped at 10 seconds, at most 10 requests and a 90-second overall startup budget. Each request gets at most 20 seconds or the remaining budget. It displays a connection status and disables duplicate submissions. Uploads and decision requests are not automatically replayed. Missing configuration, 403/429 responses and invalid CSRF output are not retried.

Verification: **22 retry-safety checks and 56 browser checks passed**. Through the actual public Cloudflare API, a synthetic Microsoft DOCX was accepted (202), queued, processed and returned a valid 124-word letter at 28.25 seconds from session setup. The draft was rejected (200), and another visitor was denied access (404). The complete check, including rejection/isolation, took 39.59 seconds. No application was approved or saved. This checks the connected queue path, not whether Render has an independently running worker; other existing workers can consume the shared queue. Approved document downloads were not retested in this run.

The frontend fix requires Cloudflare Pages to build the new commit. No n8n/backend/database change is needed for this fix. Bounded retries improve startup recovery; they do not remove hosting cold-start delays or guarantee instant generation.

## Current published one-call workflow, 2 November 2026

The current generation import is [workflows/simple/Final Orchestrator.json](../workflows/simple/Final%20Orchestrator.json). Its README includes exact import and saved-credential setup. The simple/ folder name distinguishes this website-compatible design from earlier final/ and fast/ references; the workflow name remains **Final Orchestrator**.

- One Gemini 3.5 Flash-Lite POST sends a strict provider response schema. Matching, drafting and explicitly labelled same-model self-review share that response; it is not an independent critic.
- All **15/15 role generations passed on their first attempt** in a published-webhook test; all **7/7 invalid-request cases passed**. There were no JSON/schema failures in that run and no automatic generation retries.
- Actual webhook times: **2.698-6.334 seconds**, median **2.940 seconds**. Exact final-letter MCP word count/hash, role/source version, deadline, usage and the actual Python response contract passed for each result.
- **216 local workflow checks**, 30 backend unit tests and real n8n-expression/live-MCP replay checks passed. Replay Gemini/sanitization were simulated; the separate published role matrix used real Gemini.
- Frontend URL: https://ai-internship-application-coach.pages.dev ; backend URL: https://ai-internship-application-coach.onrender.com . The n8n production webhook path and backend bearer token stay unchanged.
- This revision changed workflow files/tests/documentation only. No new backend code, database migration or manual Cloudflare/Render deployment is required. Git-connected hosts may rebuild automatically according to their configured settings.
- The complete deployed website upload -> queue -> approval -> PDF/DOCX/TXT journey, concurrency and provider outages were not retested in this run. Measurements do not guarantee future latency, availability or factual quality. No applications were saved or approved during the synthetic webhook matrix.

See [machine-readable results](../workflows/simple/TEST-RESULTS.json). Older results below describe the earlier 1 November checkpoint and are retained as history.

## Connected locally, historical checkpoint

- FastAPI: http://127.0.0.1:8010/ ; readiness reports database, private sessions and coaching configured. This is local development, not a deployed public service.
- API, queue worker and management services use three separate Supabase session-pooler login accounts. Each inherits only internship_api, internship_worker or internship_operator. All use verified TLS with the public Supabase CA; none is administrator or RLS bypass. Passwords, connection URLs, session/encryption secrets and webhook token remain in ignored local environment files.
- The published development n8n MCP endpoint is `/mcp/final-career-tools`; the Orchestrator production webhook is `/webhook/final-internship-coach` on zeeshan1786.app.n8n.cloud. Backend requests use server-only Bearer authentication and an Idempotency-Key. Clicking Execute on the webhook canvas waits for a request; it does not synthesize one.
- Queue processing happens outside HTTP intake. A database-backed global lease limits work; the controller starts/drains bounded thread executors with a development ceiling of two concurrent jobs. This does not implement hosting instance scale-to-zero.

## Verification evidence

| Check | Result | Scope |
| --- | --- | --- |
| Backend pytest with FIRSTROLE_INTEGRATION=1 | 32 passed | Includes real Supabase approval/rejection, exact downloads and cross-owner isolation |
| Python dependency consistency | Passed | pip check |
| Frontend browser suite | 52 passed | Mocked API responses, not live provider generation |
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

## Remaining work at the 1 November checkpoint

Diagnose the intermittent queue-driven Amazon PDF failure; extend live checks to all 15 roles and concurrent clients; configure Cloudflare/Render routing and cookie behavior; remove the development frontend catalog fallback for public launch; add retention/recovery and backup checks; reconcile environment-specific authentication migration history before automated database deployment. No Cloudflare/Render publication or automatic GitHub-to-n8n deployment is enabled.

The current schema and educational role sources are versioned under supabase/ and role_documents/. Runtime-specific login provisioning and private n8n credential bindings are deliberately separate from those reusable files. The original v1.0.0 tag is preserved as historical checkpoint.
