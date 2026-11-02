# Firstrole frontend

Version **1.0.0** is the initial frontend release. The deployed frontend connects through its same-origin Cloudflare API proxy to the Python backend and Supabase. See the current integration report for live-test scope.

Local frontend for the AI Internship Application Coach. Matches the approved forest-green and ivory preview. The initial screen has no generated letter: upload a PDF/DOCX, select a company and role, and enter the signature name on one page.

## Run locally

Use a current Node.js LTS release:

```sh
cd frontend
npm run dev
```

Open http://127.0.0.1:5173/. No installation is required to run the static frontend. Do not open index.html directly through file://; ES modules and the role catalog need an HTTP server.

The local server serves static files only. Without the Python API, you can inspect the form and all 15 fictional roles. Generate shows a clear connection error. It never generates a sample letter or pretends to save an application.

## Folder structure

```text
frontend/
  index.html
  assets/
    css/styles.css
    data/roles.json
    js/
      app.js                  # Screen flow and analysis polling
      api.js                  # Same-origin API requests and CSRF header
      state.js                # In-memory state and safe letter rendering
      components/
        intake.js             # Upload validation and dependent role selection
        review.js             # Editing and explicit review confirmation
        approval.js           # Server-confirmed approve/reject decisions
        downloads.js          # Approved server exports and clipboard
  tools/dev-server.mjs         # Local static server
  tests/browser-check.cjs      # Browser checks with synthetic API responses
  API_CONTRACT.md
  package.json
```

## What is implemented

- PDF/DOCX selection, drag-and-drop, one-file and 5 MB checks. The backend must still inspect actual file contents.
- Five companies with three dependent roles each; public catalog fallback when the API is unavailable.
- Actual API submission, queued analysis polling, failure feedback, and retrying a known analysis without re-uploading.
- Plain-text letter editing. Body paragraphs are justified; greeting and signature stay left aligned.
- Editing invalidates the approval checkbox. Incomplete placeholders and letters over 250 words block approval.
- Approval remains pending until the backend confirms it saved the exact approved text. Rejection never unlocks download.
- DOCX, PDF and TXT requests use server exports; no synthetic files are disguised as document downloads.
- Keyboard focus states, status announcements, mobile layouts and reduced-motion support.

## Current storage and integration limits

The standalone static preview has no database connection. In the deployed application, the Python backend stores encrypted uploads/analyses and approved letters in Supabase with server-enforced visitor ownership. The browser keeps form/draft UI state in memory; its HttpOnly session cookie grants access to private records. No private resume/letter content or server secrets belong in Git or browser storage. Refreshing clears the unsent form and draft UI.

The fictional role catalog is a public JSON file. Browser checks create synthetic test responses in isolated browser contexts; those are not live AI, database or document export tests.

The Python backend creates anonymous sessions, authorizes each private record, validates files, runs the queued n8n pipeline, stores approved applications and produces genuine document exports. Serve this folder and `/api` through one origin. See API_CONTRACT.md. There are no API keys or database credentials in this folder.

No-login access persists only as long as the server-issued session cookie survives. Another browser/device or clearing cookies loses access unless a separate recovery mechanism is added. Session ownership must be enforced by the backend; client IDs alone are not authorization.

## Browser checks

```sh
npm install
npx playwright install chromium
npm test
```

On Windows the runner can use installed Microsoft Edge. Set `PLAYWRIGHT_EXECUTABLE_PATH` for another Chromium executable if needed. The test starts its own localhost server and uses synthetic resumes and mocked API responses. It checks all role options, upload validation, safe rendering, processing, exact-version approval, failed saves, rejection, downloads, fresh analyses and narrow screens. It does not prove database isolation or AI quality.

## Production serving

Use the Python application or a reverse proxy for static files and same-origin API routing; the included server is for local development. Use HTTPS, no caching of private API responses, secure session cookies and appropriate response headers. Preserve paragraph justification in the backend DOCX/PDF export templates as well as in this browser view.

The configured hosts are Cloudflare Pages for the frontend, Render for the Python API, and Supabase for PostgreSQL. The Cloudflare Pages function forwards same-origin `/api` requests to Render. A separate durable queue worker must remain available; the API is not itself a worker. Do not deploy the local Node development server as the production backend. Publish only intended frontend assets, not the test scripts or development tools.

## API startup recovery

Before sending a resume, session setup retries only transient GET network/502/503/504 errors for at most 10 attempts within 90 seconds. The UI shows a connection status and prevents duplicate submissions. Per-attempt timeout is bounded by 20 seconds and the remaining overall budget. Once a valid session is created, only one upload is sent. Uploads and approval/rejection decisions are never automatically replayed. Authentication errors, rate limits, missing configuration and malformed CSRF responses are not retried.

`npm test` runs 22 deterministic session-recovery checks and 56 browser checks using synthetic API responses. The live deployed synthetic upload/generation/rejection/isolation result is recorded in `../docs/INTEGRATION_STATUS.md`. Changes to this frontend need a new Cloudflare Pages build; committing an n8n JSON file alone does not redeploy n8n.
