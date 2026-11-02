# AI Internship Application Coach Version 1

Firstrole helps a visitor upload a resume, select an internship, review a tailored cover letter, and approve the exact version to download.

**The original v1.0.0 tag is a development checkpoint.** The current published coaching workflow is [Final Orchestrator](workflows/simple/README.md), using one Gemini 3.5 Flash-Lite request with a provider-enforced response schema and real MCP role/deadline/word-count evidence. On 2 November 2026, all 15 role generations passed on the first attempt and all 7 invalid-request cases passed. Measured webhook latency was 2.698-6.334 seconds (median 2.940); this is not a latency guarantee. See [test results](workflows/simple/TEST-RESULTS.json), [integration status](docs/INTEGRATION_STATUS.md), [the original checkpoint](docs/VERSION_1.md) and [the changelog](CHANGELOG.md).

The frontend is deployed at https://ai-internship-application-coach.pages.dev and the backend at https://ai-internship-application-coach.onrender.com. This workflow revision requires no frontend/backend/database changes or manual hosting redeployment. The full deployed upload/approval/download journey was not retested with this revision.

## Project structure

| Folder | Contents |
| --- | --- |
| [`frontend/`](frontend/) | Single-page upload, review, approval and download UI |
| [`backend/`](backend/) | FastAPI routes, private sessions, encrypted uploads, durable worker and exports |
| [`supabase/`](supabase/) | Eight applied database migrations, CLI configuration, project reference and SQL tests |
| [`role_documents/`](role_documents/) | Five fictional educational role-source documents |
| [`workflows/`](workflows/) | Current [Final Orchestrator and setup](workflows/simple/README.md), supporting MCP/search workflows and earlier design references; credentials are configured separately from source |
| [`docs/`](docs/) | Project guide, deployment decisions, worker-management plan and version checkpoint |

## Frontend version 1

The initial frontend is in [`frontend/`](frontend/). It includes the upload form, company/role selection, processing and review screens, editing, approval/rejection and download controls.

```sh
cd frontend
npm run dev
```

Open http://127.0.0.1:5173/. Running the static frontend needs Node.js but no dependency installation. See the [frontend README](frontend/README.md) for tests, the API contract and integration details.

**Current status:** the local FastAPI API and durable worker connect to Supabase Mumbai using separate restricted database logins with verified TLS. The worker calls the published authenticated n8n Orchestrator, which uses Gemini 3.5 Flash-Lite and real MCP search/date/word-count tools. The Microsoft DOCX flow passed real upload, generation, approval and exact TXT/DOCX/PDF downloads. Backend tests: 32 passed; frontend mocked-API checks: 52 passed. Read the integration report for historical queue tests and current validation limits. The catalog remains fictional educational data. The published one-call Orchestrator has separate all-role webhook results; these do not prove the entire deployed queue/UI journey.

## Stack

- Frontend: HTML, CSS and JavaScript modules, hosted on Cloudflare Pages.
- Backend: Python FastAPI API and background worker, hosted on Render.
- Database: Supabase PostgreSQL with persistent role retrieval and queued jobs.
- AI processing: n8n coaching workflow and MCP tools.

The backend implements durable queues and dynamic worker management. Cloudflare Pages proxies same-origin /api requests to Render. API and worker deployments need their existing private environment settings. Git pushes may trigger hosting rebuilds if enabled in the hosting account; exporting or committing workflow JSON does not publish it to n8n.

The Supabase development project is in Mumbai. Its schema and non-secret project reference are in [`supabase/`](supabase/); [authenticated repository linking](supabase/REPOSITORY_LINK.md) is a separate pending step. Private data, local environment files, virtual environments, passwords and encryption keys are excluded from Git.
