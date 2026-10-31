# AI Internship Application Coach

Firstrole helps a visitor upload a resume, select an internship, review a tailored cover letter, and approve the exact version to download.

## Frontend version 1

The initial frontend is in [`frontend/`](frontend/). It includes the upload form, company/role selection, processing and review screens, editing, approval/rejection and download controls.

```sh
cd frontend
npm run dev
```

Open http://127.0.0.1:5173/. Running the static frontend needs Node.js but no dependency installation. See the [frontend README](frontend/README.md) for tests, the API contract and integration details.

**Current status:** this release contains the frontend only. The Python API, Supabase database and n8n integration are not connected. The local role catalog is fictional development data. Generation reports the missing backend rather than displaying a sample letter or claiming an application was saved.

## Planned stack

- Frontend: HTML, CSS and JavaScript modules, hosted on Cloudflare Pages.
- Backend: Python FastAPI API and background worker, hosted on Render.
- Database: Supabase PostgreSQL with persistent role retrieval and queued jobs.
- AI processing: n8n coaching workflow and MCP tools.

The backend plan includes durable message queues and dynamic worker management. Hosting and production API/session routing are future implementation steps; this commit does not deploy the application.
