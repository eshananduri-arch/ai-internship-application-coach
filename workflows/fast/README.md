# Fast internship coach workflows

Opt-in replacement based on the previous Workflow 2 Fast Internship Coach: one model call followed by deterministic validation and explicit human approval. This folder is separate from workflows/final/ and does not deploy or overwrite anything.

## What changed

| Component | Final design | Fast design |
| --- | --- | --- |
| Role retrieval | Generate a query embedding, then vector similarity | Read existing indexed text by exact selected role ID/version |
| Generation | Matcher, writer, independent critic: three Gemini calls | One Gemini 3.5 Flash-Lite call: match, draft, same-model self-review |
| Evidence | Exact-role sources, resume quotes, MCP deadline/count | Retained; PDF whitespace differences are normalized for quote comparison |
| Approval | Explicit visitor confirmation in Python | Unchanged |

No new tables, permissions, database passwords, model keys or Python contract changes are needed. The model still receives the current uploaded resume; no sample resume, prewritten cover letter or shared private memory is used. Same-model self-review is explicitly labelled with independent_reviewer=false; it is less assurance than a separate critic.

## Import in this order

1. Import **Fast Role Search.json** as a new workflow. In **Read Indexed Role**, select the existing **Firstrole Knowledge Reader** credential. Publish it. To test this helper directly, choose **Test Search Manually** from the Execute dropdown. Its sample input is isolated from the MCP trigger; actual user requests never inherit that sample.
2. Open the existing **Final MCP** -> **search_internship_roles**. Select **Fast Role Search** as its workflow and publish that change. Update the tool description to: `Retrieve indexed internship documents by exact selected role_id and catalog_version. Returns ok:false if no matching source exists; never substitutes another role.` Keep the server path, authentication and the other two tools unchanged.
3. Import **Fast Orchestrator.json** as a new workflow. Select **Firstrole Backend Header** in Receive Coach Request; **Firstrole MCP Header** in Search Selected Role, Check Deadline and Count Exact Final Letter; and the existing **Google Gemini (PaLM) API** credential in **Gemini One Call**. Publish it. No credentials or credential IDs are embedded in the imports.
4. Copy the new webhook's **Production URL**. With the existing n8n host and provided path it is `https://zeeshan1786.app.n8n.cloud/webhook/fast-internship-coach`. Change **N8N_WEBHOOK_URL** on both the Render API and the Render queue worker (or their shared environment group) to that URL. Keep the existing N8N_WEBHOOK_TOKEN unchanged. Have the deployment owner apply/restart those service settings. Updating only the API does not change the worker's model calls.
5. Run **Final Verification**, then submit a fresh resume through the website. Do not click Execute and expect a webhook workflow to synthesize input.

Knowledge Loader, Verification and Error Monitor remain the existing workflows. The source text must already be indexed; rerun Knowledge Loader only when role sources change. Verification's current 15-role/version-1 catalog restrictions remain unchanged.

## Performance and verification

The design has exactly one Gemini HTTP request, one read-only role database query, no query-embedding request, no agent loops, and three explicit MCP calls for actual role/deadline/final-word-count evidence. Output is capped at 1000 model tokens and a 250-word complete letter. No uncertain model request is silently retried.

Local checks passed (130 structural/contract/safety assertions). The exact SQL was tested with the restricted reader against all 15 current indexed roles; absent roles and wrong source versions returned no substitute documents. Median lookup in that check was 0.021 seconds (maximum 0.063); these are database measurements, not end-to-end n8n timings. A mocked one-call response passed the existing actual Python backend validator. Tests block unsupported evidence, failed self-review, placeholders, overlong/wrong-role letters, truncated output and a mismatched final-letter hash.

The new fast webhook has **not** been imported, published or timed live. Five seconds is a warm-path target, not a guarantee; three MCP round trips, provider response time, queue occupancy and hosting cold starts still count. This change does not remove the observed Render startup delay or the frontend's 30-second request timeout. Measure from a fresh upload after deployment, separately from backend cold-start time.

```sh
python workflows/fast/build.py
node workflows/fast/tests/check-fast.mjs
```

Keep the original published Final Orchestrator for rollback. To roll back generation, restore the previous N8N_WEBHOOK_URL in both API and worker settings. The exact-role helper remains compatible with the existing backend response contract. Never put resume files, letters, .env files or secrets in these imports or Git.

## Manual-input correction

The helper now has two separate entry points: Receive Search for real caller data, and Test Search Manually -> Manual Test Input for an explicit sample test. Both pass through the same strict validator and real database lookup. Null/missing role_id on the caller path remains an error; it is never replaced with a default. Existing published MCP calls passed for all 15 roles. The corrected manual trigger still needs importing/publishing in your n8n account; remote manual execution is not claimed as tested.
