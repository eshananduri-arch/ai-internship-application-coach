# Changelog

## Integration update — 1 November 2026

- Connect local API, queue worker and operator services to Supabase with separate restricted logins; secrets remain outside Git.
- Add the public Supabase CA and configurable verified TLS for all four connection pools, plus a connection-check script.
- Connect the authenticated published n8n webhook; preserve safe pipeline failure codes without logging private provider payloads.
- Add six portable final workflow imports, an import ZIP, setup instructions, and Code/parser checks. Generation uses Gemini 3.5 Flash-Lite with bounded model calls and explicit MCP evidence.
- Add a reproducible frontend test lockfile and current integration/verification notes.

Validation: 32 backend tests (including live PostgreSQL isolation/decision tests), 46 frontend mocked-API checks, six workflow structures, 26 Code scripts and 12 MCP envelope cases pass. The live Microsoft DOCX approval/download journey passed; broader end-to-end results and the PDF queue issue are documented in docs/INTEGRATION_STATUS.md. Original v1.0.0 remains unchanged. No hosting deployment is included.

## Version 1.0.0 â€” 31 October 2026

Development checkpoint covering the frontend, backend, Supabase database definition, source documents, tests and draft MCP tools. This checkpoint is not a production deployment or an end-to-end working AI release.

- Frontend upload/company/role form, progress, editable review, explicit approval/rejection and download screens.
- Python FastAPI API, private visitor sessions, resume encryption, validated PDF/DOCX extraction, exact-text approval and genuine DOCX/PDF/TXT exports.
- Durable Supabase queue consumer, globally leased dynamic worker capacity, throttling/retry recovery, token reservations and protected management endpoints.
- Eight applied Supabase migrations, five fictional companies, 15 demo roles and five source documents. Real embeddings remain pending.
- Draft n8n MCP server export and deterministic date/word-count tools, with no credentials or pinned private data.
- Project/deployment/worker plans, API and n8n contracts, verification reports and local test suites.

Validation: 27 Python checks passed, two real-database HTTP tests skipped, 49 live database SQL checks passed, 46 mocked-API frontend checks passed, and 278 local MCP tool/workflow checks recorded. Document exports were rendered and visually inspected.

Remaining: configure existing approved runtime database credentials; build and publish the actual n8n API workflow; index role sources; integrate and test all roles and the complete user journey; then deploy/publish. No new database logins were created. No Cloudflare/Render deployment or automatic Supabase deployment is enabled by this checkpoint.
