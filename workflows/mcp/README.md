# Internship Career Tools import

Import `../Workflow 2 Internship Career Tools.json` into the intended new n8n account. The workflow is inactive and has no embedded credentials, account-specific URLs, pinned data, previous workflow IDs or synthetic role content.

## After import

1. Open **MCP Server**. Create/select **HTTP Header Auth** with the header name `X-Internship-MCP-Key` and a long random secret. Keep it in n8n credentials, not JSON or chat. Trusted clients must send the same header.
2. Open **search_internship_roles** and create/select the PostgreSQL knowledge credential. Use the hosted database connection details and its required verified TLS configuration. Never disable certificate verification to work around a connection problem.
3. Open **Gemini Embeddings** and create/select the Google Gemini API credential. The selected model is `models/gemini-embedding-001`; the future loader must use this same model and 3072 dimensions.
4. The current Mumbai Supabase project already has the knowledge tables through `../../supabase/migrations/`; do not rerun `prepare_knowledge_database.sql` there. That bootstrap is retained only as an earlier standalone setup artifact. A separate Knowledge Loader workflow must populate the existing schema. Creating tables does not load documents or generate embeddings.
5. Publish the workflow and open MCP Server → **Production URL** → copy the actual URL. The path is `internship-career-tools`. Do not use the test URL for deployment.
6. Configure a trusted MCP client with that production endpoint, the same header credential and only the tools needed by its agent. Test the tools before connecting the full coaching pipeline.

You can import before the database exists. Publishing still requires the credentials demanded by the nodes; publishing alone does not prove search works. Date/word tools do not query PostgreSQL or call an LLM. Role retrieval needs PostgreSQL, indexed documents and the embedding credential. No actual import, publication, credential or database connection was tested in the new account while producing this file.

## Tools

### search_internship_roles

```json
{ "input": "NVIDIA NVIDIA-01 AI/ML Intern requirements and deadline", "role_id": "NVIDIA-01" }
```

Persistent PostgreSQL vector retrieval. The dataset and exact `role_id` are metadata filters; the query text alone is not the filter. Returns up to three role chunks with their metadata. Unknown/unindexed IDs return no documents; the caller must report role_not_found rather than use another role. The calling API must also verify that the returned role is the visitor's selected role.

Each stored chunk must describe a single role and have `dataset: internship_roles`, `role_id`, `company`, `source_title` and `source_version`. Retrieve three chunks, not three unrelated roles. The loader must replace obsolete versions safely; do not mix old and new versions or embedding models.

### days_until

```json
{ "input": "2026-12-15" }
```

Returns an exact calendar-day difference from the actual current date in Asia/Kolkata. It validates real dates, including leap years; expired dates return negative days. The date is calculated at tool execution, not hardcoded when exported. A closing hour is not inferred. Empty or invalid dates return structured errors.

### word_count

```json
{ "input": "Dear Hiring Team,\n\nThe exact letter body.\n\nSincerely,\nCandidate Name" }
```

Returns whitespace-based word count, 250-word limit status and a SHA-256 digest of the actual text. It normalizes CRLF/CR line endings to LF, with no other rewriting. The critic/API must compare the digest to the final letter using the same normalization. It does not prove MCP was called; the calling workflow must retain structured call evidence. Recount after any change to the final letter. Empty text is marked nonempty=false; it is not a valid cover letter.

All three tool names come from node names. Keep these names unchanged when connecting future clients.

## Verification performed locally

The validation script checks JSON structure, node connections and schemas, credentials being absent, persistent-store settings, all 15 catalog IDs against the configured role filter contract, date edge cases and SHA-256 against Node's built-in crypto implementation. This is not a live n8n execution or database retrieval test.

Run from this directory with Node:

```sh
node tests/validate.cjs
```

Before calling this workflow fully verified, perform a live authenticated tools/list and tools/call, query an indexed and unknown role, confirm source metadata, test a deadline and count a known exact letter. Verify wrong credentials fail. Test all role IDs after the future loader populates the database.

## Private data and source notes

Successful, failed and manual execution-payload saving is disabled in the import settings because word_count receives letter text. Do not enable detailed saved traces on real resumes/letters without an intentional retention policy. Synthetic test data can be used temporarily for debugging. Credentials and knowledge data live outside the workflow JSON; n8n's own operational storage is separate from the application's PostgreSQL database.

The metadata filter uses `$fromAI('role_id', ...)` and the vector-store tool's modern structured input handling. The file uses MCP Server Trigger v2, PGVector Store v1.3, Code Tool v1.2 and Gemini Embeddings v1. Confirm these are supported in the target account; if n8n flags an unsupported node/version, stop and inspect it rather than replacing it with a lookalike node or claiming the import worked.

Primary references checked when creating the file:

- [MCP Server Trigger](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-langchain.mcptrigger/)
- [Postgres PGVector Store](https://docs.n8n.io/integrations/builtin/cluster-nodes/root-nodes/n8n-nodes-langchain.vectorstorepgvector/)
- [Custom Code Tool](https://docs.n8n.io/integrations/builtin/cluster-nodes/sub-nodes/n8n-nodes-langchain.toolcode/)
- [Official n8n implementation](https://github.com/n8n-io/n8n/tree/master/packages/%40n8n/nodes-langchain)
- [Google embedding model documentation](https://ai.google.dev/gemini-api/docs/embeddings)
