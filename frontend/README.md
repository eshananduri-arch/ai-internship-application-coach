# Firstrole frontend

Version **1.0.0** is the initial frontend release. Backend and database integration are pending.

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

**There is no connected database or Python backend in this frontend deliverable.** Files, draft text and application IDs exist only in this tab's JavaScript memory. No resume or letter is written to localStorage, sessionStorage, browser databases, cookies, Git, or the local development server. Refreshing loses the current form and draft.

The fictional role catalog is a public JSON file. Browser checks create synthetic test responses in isolated browser contexts; those are not live AI, database or document export tests.

The next phase is a Python backend and PostgreSQL. Serve this folder and `/api` through one origin. The backend must create anonymous sessions, authorize every private record by session, validate files, run the n8n pipeline, store approved applications, and generate real document exports. See API_CONTRACT.md. There are no API keys or database credentials in this folder.

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

The planned hosts are Cloudflare Pages for the frontend, Render for the Python API/worker, and Supabase for PostgreSQL. A same-origin API proxy or another reviewed session-routing design is needed before connecting those hosts. Do not deploy the local Node development server as the production backend. Publish only intended frontend assets, not the test scripts or development tools.
