# Changelog

## Version 1.0.0 — 31 October 2026

Development checkpoint covering the frontend, backend, Supabase database definition, source documents, tests and draft MCP tools. This checkpoint is not a production deployment or an end-to-end working AI release.

- Frontend upload/company/role form, progress, editable review, explicit approval/rejection and download screens.
- Python FastAPI API, private visitor sessions, resume encryption, validated PDF/DOCX extraction, exact-text approval and genuine DOCX/PDF/TXT exports.
- Durable Supabase queue consumer, globally leased dynamic worker capacity, throttling/retry recovery, token reservations and protected management endpoints.
- Eight applied Supabase migrations, five fictional companies, 15 demo roles and five source documents. Real embeddings remain pending.
- Draft n8n MCP server export and deterministic date/word-count tools, with no credentials or pinned private data.
- Project/deployment/worker plans, API and n8n contracts, verification reports and local test suites.

Validation: 27 Python checks passed, two real-database HTTP tests skipped, 49 live database SQL checks passed, 46 mocked-API frontend checks passed, and 278 local MCP tool/workflow checks recorded. Document exports were rendered and visually inspected.

Remaining: configure existing approved runtime database credentials; build and publish the actual n8n API workflow; index role sources; integrate and test all roles and the complete user journey; then deploy/publish. No new database logins were created. No Cloudflare/Render deployment or automatic Supabase deployment is enabled by this checkpoint.
