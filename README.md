# AI Internship Application Coach Version 1

Firstrole helps a visitor upload a resume, select an internship, review a tailored cover letter, and approve the exact version to download.

**The original v1.0.0 tag is a development checkpoint.** Current main adds verified Supabase connections and six final n8n workflow templates. Local live generation and approval/download integration has been exercised; deployment is still pending. See [current integration status](docs/INTEGRATION_STATUS.md), [the original checkpoint](docs/VERSION_1.md) and [the changelog](CHANGELOG.md).

## Project structure

| Folder | Contents |
| --- | --- |
| [`frontend/`](frontend/) | Single-page upload, review, approval and download UI |
| [`backend/`](backend/) | FastAPI routes, private sessions, encrypted uploads, durable worker and exports |
| [`supabase/`](supabase/) | Eight applied database migrations, CLI configuration, project reference and SQL tests |
| [`role_documents/`](role_documents/) | Five fictional educational role-source documents |
| [`workflows/`](workflows/) | Original draft plus [final import package and manual setup](workflows/final/README.md); credentials are configured separately from source |
| [`docs/`](docs/) | Project guide, deployment decisions, worker-management plan and version checkpoint |

## Frontend version 1

The initial frontend is in [`frontend/`](frontend/). It includes the upload form, company/role selection, processing and review screens, editing, approval/rejection and download controls.

```sh
cd frontend
npm run dev
```

Open http://127.0.0.1:5173/. Running the static frontend needs Node.js but no dependency installation. See the [frontend README](frontend/README.md) for tests, the API contract and integration details.

**Current status:** the local FastAPI API and durable worker connect to Supabase Mumbai using separate restricted database logins with verified TLS. The worker calls the published authenticated n8n Orchestrator, which uses Gemini 3.5 Flash-Lite and real MCP search/date/word-count tools. The Microsoft DOCX flow passed real upload, generation, approval and exact TXT/DOCX/PDF downloads. Backend tests: 32 passed; frontend mocked-API checks: 46 passed. Read the integration report for the unresolved PDF queue test and validation limits. The catalog remains fictional educational data. Cloudflare/Render deployment and a public launch have not happened.

## Planned stack

- Frontend: HTML, CSS and JavaScript modules, hosted on Cloudflare Pages.
- Backend: Python FastAPI API and background worker, hosted on Render.
- Database: Supabase PostgreSQL with persistent role retrieval and queued jobs.
- AI processing: n8n coaching workflow and MCP tools.

The backend implements durable queues and dynamic worker management. Hosting and production API/session routing are future integration steps. No automatic deployment is enabled by this source checkpoint.

The Supabase development project is in Mumbai. Its schema and non-secret project reference are in [`supabase/`](supabase/); [authenticated repository linking](supabase/REPOSITORY_LINK.md) is a separate pending step. Private data, local environment files, virtual environments, passwords and encryption keys are excluded from Git.
