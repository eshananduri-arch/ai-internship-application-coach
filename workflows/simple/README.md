# Final Orchestrator - structured JSON correction

Only Final Orchestrator changes. The backend, frontend, database, queue worker, MCP server, role search, knowledge loader, verification and error-monitor workflows do not need changes for this correction.

## Change

The former native Google Gemini Message a Model operation enabled JSON mode but did not forward the response schema. In live tests, 13/15 role generations passed first try; two failed with model_invalid_schema/model_invalid_json and passed separate rechecks. These were real failures, not successful first attempts.

The generation node is now **Gemini One Call - Structured JSON**, an HTTP Request using the existing Google Gemini(PaLM) API credential. It sends Google's documented generationConfig.responseFormat.text.schema directly to Gemini 3.5 Flash-Lite. The schema requires all six result fields, restricts nested keys, bounds array sizes and constrains fit values. There is exactly one generation POST, one candidate, 1536 maximum output tokens, no tools, no automatic repair model and no automatic generation retry.

The HTTP node is deliberate: the native Message a Model operation does not expose this schema setting. It is still one real Gemini text-generation request. Real provider HTTP status and usageMetadata are retained. Request and response Code nodes use simple prebuilt-field expressions compatible with the real n8n expression engine.

Application validation remains mandatory: exact selected role/version, current resume evidence quotes, deadline, unsupported claims, missing/invalid/truncated JSON, failed self-review, word limit, placeholders, exact final-letter MCP hash/count and real token accounting. Structured JSON constrains format; it cannot guarantee factual quality, successful provider availability or response latency.

## Import into the existing workflow

1. Back up the current Final Orchestrator using its menu -> Download. On the canvas select and delete its old nodes, then use the menu -> Import from File -> Final Orchestrator.json. Keep the workflow name **Final Orchestrator**. Do not append another copy alongside the existing nodes.
2. Select the existing saved credentials. No new key or credential is needed:

| Node | Existing credential |
| --- | --- |
| Receive Coach Request | Header Auth: Firstrole Backend Header (Authorization header with Bearer and the backend token) |
| Open MCP Session; Mark MCP Ready; Search Selected Role; Check Deadline; Count Exact Final Letter; Close MCP Session | Header Auth: Firstrole MCP Verified (X-Internship-MCP-Key header) |
| Gemini One Call - Structured JSON | Predefined Credential Type -> Google Gemini(PaLM) API -> your working Google API credential |

3. Save and Publish. The MCP URL and model are prefilled. The production URL stays https://zeeshan1786.app.n8n.cloud/webhook/final-internship-coach, so the backend/worker URL and token need no change. Ask the assistant to test; you do not need to construct a test request or run each helper workflow.

No credential IDs or secret values are embedded in the import. Existing authorization must stay enabled; the backend header and MCP header are different credentials.

## Verification and limits

216 local structural, privacy, schema, invalid-input, provider-envelope, truncated-output, usage, evidence and backend-contract checks passed. Offline fixtures use their captured calendar day so tomorrow's date does not break yesterday's fixture. A replay using n8n-workflow 2.16.0 evaluated all 18 expressions and passed actual MCP initialization, notification, role lookup, deadline, exact word count/hash and session deletion. Gemini and sanitization were simulated in that replay. The real Python Coach.validate accepted the revised flow's simulated result.

The revised published workflow was tested with real Gemini and synthetic resumes: all 15 roles passed on the first attempt, and all 7 invalid-request cases returned the expected safe 422/403 status. There were zero JSON/schema failures in this matrix, and exactly one Gemini invocation per successful request. Generation request time was 2.698-6.334 seconds (median 2.940). Two additional targeted tests of the previously failing NVIDIA roles passed in 5.848 and 3.722 seconds. These are measurements from this run, not guaranteed latency or proof that future provider failures cannot occur. The full website upload/approval/download sequence was not retested; no applications were saved or approved.

Browser control failed with a sandbox-helper/kernel error, so the assistant could not apply the correction to n8n directly. No workflow was published, no database changed and no files were pushed to GitHub by this preparation.

## Sources

- https://ai.google.dev/gemini-api/docs/generate-content/structured-output?hl=en
- https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.httprequest/
- https://github.com/n8n-io/n8n/blob/master/packages/@n8n/nodes-langchain/nodes/vendors/GoogleGemini/actions/text/message.operation.ts
- https://github.com/n8n-io/n8n/blob/master/packages/@n8n/nodes-langchain/credentials/GooglePalmApi.credentials.ts

## Reproduce the live role matrix

With the existing production N8N_WEBHOOK_URL and N8N_WEBHOOK_TOKEN configured only in ignored backend/.env, run from the repository root:

```powershell
backend/.venv/Scripts/python.exe workflows/simple/tests/live-generation.py --live
```

This explicitly sends 15 real synthetic-resume generation requests and 7 invalid-request cases. It consumes model tokens. No applications are approved or saved; reports go only to ignored backend/test-artifacts/structured-json/. Without --live the script refuses to make requests. Run the offline suite with `node workflows/simple/tests/check-simple.mjs`. The optional real-expression replay requires the n8n-workflow 2.16.0 runtime and existing MCP key; it simulates Gemini and is not the live generation matrix.
