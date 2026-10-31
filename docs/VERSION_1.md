# Version 1 development checkpoint

Version: **1.0.0**. Recorded 31 October 2026, Asia/Kolkata. Git tag: **v1.0.0**.

Firstrole accepts a resume and company/role selection, generates a reviewed cover letter through a future n8n integration, and saves/downloads the exact version a visitor approves. The user-facing application has no login page.

## Progress at this checkpoint

| Component | Implemented | Remaining integration |
| --- | --- | --- |
| Frontend | Form, progress/review/edit screens, decisions, downloads | Complete live API flow, recent-record UI and production catalog fallback removal |
| Python backend | API routes, private cookie sessions, encrypted resume handling, approval transactions, exports | Existing approved runtime database credential and live n8n webhook |
| Queues and workers | Durable pgmq jobs, leased global capacity, dynamic threads, retries, budgets and protected management endpoints | Live cross-process Python/n8n load and failure tests; deployment wakeup/cost checks |
| Supabase | Mumbai project, eight migrations, catalog/source records, private tables, RLS and runtime SQL helpers | Runtime credential setup, real role embeddings, production operational checks |
| n8n | Draft MCP JSON/tools and the server-to-server contract | Import, credentials, knowledge loader, coaching workflow, publication and real execution evidence |
| Hosting | Cloudflare Pages + Render selected | Integration, tests, then reviewed deployment |

The local server can show the frontend and liveness endpoint. Readiness is currently false. Generation cannot work end to end until both the database runtime connection and n8n are configured. No synthetic AI response is used in the running app.

## Verification

- 27 Python tests passed; two database-backed HTTP tests skipped because runtime database credentials are missing.
- 49 live Supabase SQL checks passed through the connected administrative tool. Fixtures and queue messages were rolled back.
- 46 frontend checks passed with mocked API responses.
- 278 local deterministic MCP/workflow checks are recorded; live import and retrieval are still untested.
- DOCX/PDF exports were rendered and visually inspected. The body is justified and greeting/signature are left aligned.
- The generated session/encryption/administrator secrets were checked against Git-visible files and were absent.

These results do not claim that the Python-to-Supabase connection, real multi-agent generation, all-role live retrieval or production deployment have passed.

## Supabase and this repository

Project: [internship-coach-dev](https://supabase.com/dashboard/project/eztcigkqrhuyeyfgpaor), Mumbai (`ap-south-1`). The public project reference and connection host are recorded in `supabase/project.json`; eight versioned SQL migrations match the live migration history. No private database rows, original resumes, live session data or credentials are committed.

The CLI workspace is initialized with PostgreSQL 17. This is not an authenticated remote connection: the CLI has no access token, and dashboard GitHub authorization could not be completed through the available browser helper. See `supabase/REPOSITORY_LINK.md` for the exact outstanding link step. Automatic deployment and preview branches have not been enabled.

## Next session

1. Finish the n8n tools, knowledge indexing and authenticated coaching API workflow.
2. Configure an existing approved database runtime credential privately; leave database logins unchanged unless the user changes that decision.
3. Connect Python to Supabase and the published n8n webhook.
4. Test different resumes, all 15 roles, tool evidence, visitor isolation, queue concurrency/recovery, approval/rejection and exact downloaded wording. Measure latency without replacing required work with fake output.
5. Make integration fixes and create a new version checkpoint.
6. Review deployment configuration, secrets, backups, cost and same-origin proxy behavior, then publish later with user authorization.

The Word project guide and earlier planning notes are retained as progress artifacts. They predate some implementation details; use this checkpoint, `backend/README.md` and `supabase/README.md` for current status.
