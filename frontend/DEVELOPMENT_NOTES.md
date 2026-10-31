# Agreed implementation decisions

Project decisions for frontend version 1.0.0, updated 2026-10-31.

- Version 1 publishes the existing frontend. The Python backend, database integration and deployment remain separate implementation steps.
- Keep the current local frontend usable for development and browser checks.
- Supabase PostgreSQL is the chosen production database, with a Python backend. There is no connected database yet.
- Production role catalogs, resume records, generated letters, approval decisions and saved applications must come from the backend/database. The local JSON catalog fallback is a development aid and must be removed from production routing when those endpoints are implemented. Never fall back to fake letters or fake saved records.
- Synthetic test responses belong only in the browser test suite. Do not use them as application responses or seed real users' records with them.
- Upload resume, choose company and choose role on one page. Show a letter only after real generation finishes, then review/edit, explicit approve or reject, and download the exact approved version.
- No login page. Private ownership must be enforced through server-managed anonymous sessions. Different users must never see each other's records.
- The visual design should match the approved preview. Letter body paragraphs must be justified; salutation and signature must be left aligned, including exported documents.
- Make future frontend changes alongside the evolving API and database schema; update API_CONTRACT.md whenever the interface changes.

The planned frontend host is Cloudflare Pages; the Python API and worker will run on Render. Preserve the two backend requirements: persistent message queues and dynamic worker management with private operations controls. Production routing must preserve the same-origin /api contract and private session cookies. No hosting service is provisioned by this frontend release.
