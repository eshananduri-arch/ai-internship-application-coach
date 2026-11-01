# Final n8n workflows

Six credential-free import templates for the Python backend and Supabase catalog. Import JSON from this folder or `Final Workflows Import Pack.zip`. Existing published cloud workflows are separate from these files; a Git push does not deploy n8n. Templates are inactive on import and contain no pinned resume data or credential IDs.

| Workflow | Responsibility | Credentials |
| --- | --- | --- |
| Final Knowledge Loader | Read versioned sources, batch-embed all 15 role documents, validate vectors, then atomically replace the index | Knowledge Writer on both PostgreSQL nodes; Google Gemini API on embedding request |
| Final Role Search | Embed one query and retrieve only the selected role/version | Knowledge Reader on Read Exact Role Vectors; Google Gemini API on query embedding |
| Final MCP | Publish search_internship_roles, days_until and word_count | Firstrole MCP Header; select imported Final Role Search in the search tool |
| Final Verification | Check all 15 role searches, date calculation and exact word counting | Firstrole MCP Header on all three MCP clients |
| Final Orchestrator | Authenticated backend request, privacy sanitization, role/deadline checks, three bounded Gemini calls, exact final-letter counting, validated response | Firstrole Backend Header on webhook; Firstrole MCP Header on three MCP clients; Google Gemini API on Matcher/Writer/Critic Model |
| Final Error Monitor | Retain only safe error classification and workflow metadata | None |

## Import and publish

1. Import Role Search, Knowledge Loader, MCP, Verification, Orchestrator and Error Monitor into separate workflows. Avoid pasting a second set of nodes onto an existing canvas.
2. Create the two Postgres credentials with separate knowledge-only reader/writer login accounts. For the current project: host `aws-0-ap-south-1.pooler.supabase.com`, port `5432`, database `postgres`; usernames are `<login>.eztcigkqrhuyeyfgpaor`. Obtain passwords from the project maintainer through a private channel.
3. Set SSL Require, Ignore SSL Issues OFF, Maximum Connections 2, and paste the public CA from `backend/certs/supabase-root-2021.crt` into CA Certificate. Select the Writer in both loader SQL nodes; the Reader in Role Search. Neither login can read private resumes or approved letters.
4. Select your Google Gemini (PaLM) API credential on the five HTTP nodes listed above. The credential's legacy PaLM label does not select the model. Generation uses **gemini-3.5-flash-lite** only; embeddings use **models/gemini-embedding-001**, 3072 dimensions.
5. Create Header Auth credential Firstrole MCP Header: header name `X-Internship-MCP-Key`, value a private shared secret. Select it on the server and MCP clients. Select the real Final Role Search workflow in the MCP search tool. Publish Role Search and MCP.
6. Set the published production MCP URL centrally in Orchestrator / Workflow Settings and Verification / Verification Settings. The included development URL is `https://zeeshan1786.app.n8n.cloud/mcp/final-career-tools`.
7. Run Knowledge Loader once, then Verification. Reload knowledge after source changes; do not rerun the loader for every user upload.
8. Create Firstrole Backend Header: header name `Authorization`, value `Bearer <N8N_WEBHOOK_TOKEN>`. Select it on Receive Coach Request. Set the same private token in backend configuration. Publish the Orchestrator.
9. Set backend N8N_WEBHOOK_URL to its production POST URL; current development endpoint is `https://zeeshan1786.app.n8n.cloud/webhook/final-internship-coach`. The Python API queues uploads; the worker calls that endpoint. Clicking Execute in the editor only waits for a test webhook request.
10. Select Final Error Monitor in applicable workflow settings if desired. Do not enable raw execution retention for private resumes or letters. Monitor stores no raw payload.

No AI model is needed inside Final MCP or Final Verification. The three generation requests are HTTP nodes named Matcher Model, Writer Model and Critic Model. They use structured JSON and bounded output, with no supervisor/agent retry loop. This is a bounded pipeline; it does not claim to implement every AI Agent node requirement from the original classroom exercise.

## Backend contract and failures

See `backend/N8N_CONTRACT.md`. Each request uses the uploaded resume, server-selected role snapshot, current India date, correlation IDs, 250-word limit and a 12,000-token reservation. Tool evidence comes from actual MCP outputs. Approval and database application saves happen only in Python after the visitor explicitly approves; n8n does not approve applications or send email.

Provider latency and schema/evidence validation can reject a result. Never convert an error into success, invent a letter, remove evidence checks or automatically replay an uncertain paid request. The backend records only safe error codes. The updated template parser preserves nested tool errors instead of hiding them as invalid JSON. Updating these files does not update an already published cloud workflow.

## Local checks

```sh
node workflows/final/tests/check-imports.mjs
```

Checks all six import structures, compiles all 26 Code scripts and exercises 12 MCP response-envelope cases. These checks do not replace live n8n execution. See `docs/INTEGRATION_STATUS.md` for actual integration results and limitations.
