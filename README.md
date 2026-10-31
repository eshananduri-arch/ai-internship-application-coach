# AI Internship Application Coach Version 1

Firstrole helps a visitor upload a resume, select an internship, review a tailored cover letter, and approve the exact version to download.

**Version 1.0.0 is a development checkpoint.** It contains the frontend, Python backend, Supabase migrations, draft MCP tools and all project progress notes. The live database connection and n8n integration are still pending; this is not a production-ready AI release. See [checkpoint status and next steps](docs/VERSION_1.md) and [the changelog](CHANGELOG.md).

## Project structure

| Folder | Contents |
| --- | --- |
| [`frontend/`](frontend/) | Single-page upload, review, approval and download UI |
| [`backend/`](backend/) | FastAPI routes, private sessions, encrypted uploads, durable worker and exports |
| [`supabase/`](supabase/) | Eight applied database migrations, CLI configuration, project reference and SQL tests |
| [`role_documents/`](role_documents/) | Five fictional educational role-source documents |
| [`workflows/`](workflows/) | Draft n8n MCP workflow and deterministic tools; live setup remains pending |
| [`docs/`](docs/) | Project guide, deployment decisions, worker-management plan and version checkpoint |

## Frontend version 1

The initial frontend is in [`frontend/`](frontend/). It includes the upload form, company/role selection, processing and review screens, editing, approval/rejection and download controls.

```sh
cd frontend
npm run dev
```

Open http://127.0.0.1:5173/. Running the static frontend needs Node.js but no dependency installation. See the [frontend README](frontend/README.md) for tests, the API contract and integration details.

**Current status:** frontend version 1 is available. Supabase database version 1 is provisioned in Mumbai, with migrations and checks in [`supabase/`](supabase/). The local Python backend is implemented in [`backend/`](backend/), including the API, durable queue consumer, dynamically managed threads and approval/download routes. It runs locally, with 27 Python tests and 49 live SQL checks passed. Runtime database credentials and the n8n webhook are still unconfigured, so end-to-end generation and the two database-backed HTTP tests remain pending. The role catalog is fictional development data; no sample letter substitutes for real generation.

## Planned stack

- Frontend: HTML, CSS and JavaScript modules, hosted on Cloudflare Pages.
- Backend: Python FastAPI API and background worker, hosted on Render.
- Database: Supabase PostgreSQL with persistent role retrieval and queued jobs.
- AI processing: n8n coaching workflow and MCP tools.

The backend implements durable queues and dynamic worker management. Hosting and production API/session routing are future integration steps. No automatic deployment is enabled by this source checkpoint.

The Supabase development project is in Mumbai. Its schema and non-secret project reference are in [`supabase/`](supabase/); [authenticated repository linking](supabase/REPOSITORY_LINK.md) is a separate pending step. Private data, local environment files, virtual environments, passwords and encryption keys are excluded from Git.
