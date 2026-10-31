# PostgreSQL setup and data plan

**31 October update:** Supabase Mumbai is now provisioned. Use [`supabase/README.md`](supabase/README.md), its applied migrations and verification report as the implemented database baseline. Provider alternatives and schema proposals below are historical planning, not instructions to create a second database.

Planning date: 30 October 2026. This is a proposed setup. No database, provider account, credentials, private tables or live connection have been created by this planning step.

## Purpose in plain language

PostgreSQL is the application's durable storage service. A table is a structured collection of records, similar to a spreadsheet with typed columns and rules. A row represents one company, uploaded resume, analysis or approved application. Relationships connect those rows so a letter can be traced back to its owner, uploaded resume and selected role.

`pgvector` is an extension inside PostgreSQL. It stores numeric representations of document text, called embeddings, so the MCP search tool can retrieve relevant role passages. It is not a second database or chat memory. [pgvector](https://github.com/pgvector/pgvector).

The source documents and actual text remain stored alongside their search metadata; an embedding alone is not a replacement for the original facts.

## Hosting proposal

Use a hosted PostgreSQL service reachable by n8n Cloud and the future Python deployment, with verified TLS connections, pgvector support and an explicit backup policy. A database bound only to the developer laptop's localhost will not be reachable as localhost from n8n Cloud.

Neon is the proposed provider, subject to the user/admin selecting an account and plan. It documents pgvector and standard PostgreSQL client connections. No price, availability guarantee, free-tier retention or unlimited capacity is assumed. Check the chosen plan's storage, connection, idle behavior, backup and recovery terms before provisioning. [Neon pgvector](https://neon.com/docs/extensions/pgvector), [application connections](https://neon.com/docs/connect/connect-from-any-app).

Use a development database first, provisionally `internship_coach_dev`. Production gets a separate database/environment later. Do not put real users' resumes into test fixtures or use the production database for automated tests. Choose a region close to the Python deployment and consider n8n/model locations when measuring latency.

## Database organization

One database per environment, with two logical areas:

| Area | Tables | Access |
| --- | --- | --- |
| Shared knowledge | Company and role catalog, source documents and indexed role chunks. | MCP reads relevant knowledge; an administrator-controlled loader writes it. |
| Private application data | Anonymous owners/sessions, resumes, processing jobs, drafts, approval decisions and saved applications. | Python API and worker only, with owner checks on every private request. |

Keep `public.internship_role_chunks` exactly as configured in the MCP import. The name `public` is a PostgreSQL schema name, not permission for anonymous visitors to query it. Put private tables in an `app` schema when backend migrations are added; schemas group objects and privileges must be assigned explicitly. [PostgreSQL schemas](https://www.postgresql.org/docs/current/ddl-schemas.html).

Do not rename the existing MCP table or change vector column names without updating the workflow JSON and loader together.

## Phase A: knowledge required by the current MCP workflow

The supplied `workflows/mcp/prepare_knowledge_database.sql` prepares:

```text
public.internship_role_chunks
  id          UUID primary key
  text        actual role passage
  metadata    JSON containing source and role identifiers
  embedding   vector of 3072 numeric values
```

Metadata contract:

```json
{
  "dataset": "internship_roles",
  "role_id": "NVIDIA-01",
  "company": "NVIDIA",
  "source_title": "NVIDIA Internship Roles",
  "source_version": "1"
}
```

The MCP workflow filters on dataset and the exact selected role ID, returning document metadata for source attribution. Each chunk must contain facts for that one role. Preserve stable IDs across catalog, source documents, index and frontend selection.

Use `models/gemini-embedding-001` and 3072 dimensions consistently for loading and searching, matching the exported MCP node. Validate the actual returned dimension in the loader before insertion. Changing the embedding model requires a controlled reindex; do not mix models or obsolete document versions in this table.

At the current fifteen-role scale, start without an approximate vector index. The supplied metadata index is separate from vector search. Benchmark before adding a vector index and respect pgvector's index/type dimension limits.

The existing SQL only creates an empty store. The upcoming Knowledge Loader must read the source documents, split them, generate embeddings and insert rows with metadata. Creating a table or publishing MCP does not perform those steps.

Add authoritative company/role catalog and versioned document tables through migrations, keeping company/role dropdown data consistent with the retrieval index. A catalog version is activated only after its required documents are successfully indexed. Remove obsolete active chunks transactionally so search does not combine contradictory versions.

## Phase B: private data added with the Python backend

| Record | What it stores |
| --- | --- |
| visitors | Anonymous owner identity without a login account. |
| sessions | Hash of a random browser session secret, owner link and expiry. |
| resumes | Owner, original filename, size/type, encrypted original bytes, digest and encrypted extracted text. |
| analyses | Owner, resume/role/version links, job status, sanitized model input, draft text/version and structured review. |
| analysis_jobs | Durable queued work, attempt count, lease, heartbeat and safe failure category. |
| approval_decisions | Who approved/rejected which analysis/version, timestamp and submitted-text hash. |
| applications | Immutable exact approved text, owner, source analysis, role snapshot, hash and approval timestamp. |
| idempotency_requests | A request key bound to owner and payload, preventing duplicate generation/saves. |

For the existing 5 MB upload cap, original resume files can be stored as BYTEA rather than placing them in Git or a public web folder. Keep confidential fields encrypted with server-managed keys stored separately from PostgreSQL. Encryption-key backup/rotation and database backup are both required to recover encrypted records.

Exports are generated on demand from the saved approved text. DOCX/PDF/TXT files do not need to be stored as duplicate database objects initially. If exports are cached later, bind each cache entry to the approved-text digest and export-template version.

Draft/job storage happens before approval so processing survives refreshes and restarts. An approved application is a distinct record created only after the visitor approves. A rejection cannot create that approved record. The backend must not accept a browser's claim that it owns another visitor's analysis.

No silent cleanup of saved applications is planned. Agree retention/deletion rules for original resumes, abandoned drafts and expired sessions before production. Include explicit deletion and recent-record retrieval in the backend plan rather than relying on browser memory.

## Connection credentials

Use separate database identities instead of sharing the administrator password:

| Identity | Intended permissions |
| --- | --- |
| Migration administrator | Schema migrations and extension installation; not used by routine requests. |
| Knowledge loader | Read/write only the knowledge/catalog objects needed to index an approved source version. |
| MCP reader | Read the indexed role knowledge; no private resumes, application writes or arbitrary SQL tool. |
| Python API/worker | Required private application tables, jobs and catalog reads; no routine schema modification. |

Test the MCP reader against the actual n8n PGVector initialization behavior. Provision extensions and tables as administrator first. If the node requests an initialization privilege, inspect that specific operation and grant only what is necessary rather than replacing its credential with an administrator account.

n8n stores its database connection in a Postgres credential. Python uses a server-side environment variable/secret. Neither is placed in frontend JavaScript, committed workflow JSON or chat. The values required by n8n are host, port, database, username, password and SSL settings. Use certificate validation rather than Ignore SSL Issues. [n8n Postgres credentials](https://docs.n8n.io/integrations/builtin/credentials/postgres/).

The browser contacts Python over HTTPS; it never connects directly to PostgreSQL. Python calls n8n using a separate MCP/webhook authentication secret; that secret is not the database password.

## No-login privacy and persistence

A secure HttpOnly browser cookie identifies an anonymous visitor. PostgreSQL keeps that visitor's records across refreshes and application restarts. Every read, edit, decision and download is filtered/authorized for that owner. Knowing a record ID is insufficient.

Clearing cookies, using a different device or letting the session expire removes access to that anonymous identity unless an optional recovery mechanism is added. Database persistence alone does not solve identity recovery. Two people sharing the same browser session also share that identity. Document this clearly and decide whether to add recovery before launch.

Test with two separate browser sessions: create records in A, then attempt to read, approve and download their IDs in B. Each attempt must fail without exposing another user's details. Database backups are private too and must follow the same protection and retention policy.

## Setup sequence

1. User/admin selects the provider/account and creates the development PostgreSQL database. No paid resource is provisioned by this plan.
2. Record its non-secret connection fields and configure secret credentials directly in the appropriate dashboard or server environment.
3. Run the existing knowledge SQL as administrator. Confirm pgvector is installed and the empty table has the expected columns/dimensions.
4. Create the restricted knowledge credentials and test the n8n connection with TLS validation.
5. Run the future Knowledge Loader using approved source documents. Confirm all fifteen expected role IDs and source versions are indexed.
6. Test MCP search for a known role, a different role and an unknown ID. Verify no cross-role substitution or private data access.
7. Add the Python backend's private schema using Alembic migrations; test sessions, jobs, exact-version approval and downloads.
8. Configure production separately, with backups and a tested restore procedure before real uploads.

The immediate milestone is steps 1–4: a real development database connected to the imported MCP workflow. Role search still needs step 5 before it can return documents.

## Verification and operation

- Verify SQL on real PostgreSQL with pgvector; local JSON/code checks are not database tests.
- Confirm role/metadata filtering against every catalog ID after indexing.
- Test unique request keys, foreign keys and concurrent approve/reject requests.
- Verify queued jobs survive process restart and expired leases recover safely.
- Bound connection pools and worker concurrency to the selected provider's limits.
- Back up regularly and actually restore a development copy; persistence without tested recovery is insufficient. [PostgreSQL backup and restore](https://www.postgresql.org/docs/current/backup.html).
- GitHub contains migrations, schema definitions, sanitized workflow exports and synthetic fixtures only. It is not the running database and must never contain credentials or real resumes.
