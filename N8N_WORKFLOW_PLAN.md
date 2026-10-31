# Fresh n8n workflow plan

Planning date: 30 October 2026. Target: a fresh n8n account/workspace for the web application. No account has been created and no existing workflow has been changed by this plan.

## Boundaries

- Frontend: upload, company/role selection, visible progress, letter editing, approval/rejection and downloads.
- Python: file inspection/extraction, private sessions, durable jobs, n8n authentication, exact-text approval transactions and document exports.
- PostgreSQL: authoritative catalog, source documents and retrieval index, private uploads/analyses, decisions and approved applications.
- n8n: document indexing, narrowly scoped MCP tools and the AI coaching pipeline. It returns results to Python and does not directly write approved applications.

Use a fresh project if the new account supports projects; otherwise use consistent workflow names in its available workspace. Create fresh credentials in that account and bind imported nodes explicitly. Do not carry over old workflow IDs, credential IDs, test URLs or private execution data. Export sanitized JSON to Git when implementation is ready.

## Planned workflows

| Name | Responsibility | Runs when |
| --- | --- | --- |
| Workflow 1 Internship Knowledge Loader | Index the approved role documents into the durable PostgreSQL retrieval store. | An administrator adds or updates source documents. |
| Workflow 2 Internship Career Tools | Expose role search, deadline calculation and word count through an authenticated MCP endpoint. | The coaching agents request a tool. |
| Workflow 3 Internship Coach API | Accept Python's request, apply guardrails, match the role, draft, review and return structured output. | A visitor generates a letter through the website. |
| Workflow 4 Internship Error Monitor | Capture safe operational details from failed automatic executions. | A linked production workflow fails. |

Workflows 1–3 are the core application. Workflow 4 is operational support, not another model or processing layer on each successful request.

## Workflow 1 Internship Knowledge Loader

Proposed flow:

`Authenticated admin trigger → Validate source/version → Load documents → Split text → Embed → Upsert PostgreSQL chunks → Return indexing summary`

Use source documents owned/versioned in PostgreSQL, with document ID, role ID, company, source title and version on every chunk. Reindex only changed versions, avoid duplicate chunks, and switch the active version only after a complete successful import. Never wipe a working knowledge base before a replacement is ready.

The frontend's role catalog and document metadata must agree. For the present five-company, fifteen-role catalog, there can be five company documents containing three clearly identified roles each. If the jury requires exactly the original five fictional roles, prepare that exact catalog intentionally; do not silently claim fifteen roles match that brief verbatim.

This is an administrator operation, never a public resume-upload endpoint. Resume text is not mixed into the shared role index. Source changes require an intentional administrator action.

Dependency: PostgreSQL and a supported persistent vector extension/store configuration must be available before this workflow can pass an end-to-end indexing test. Validate embedding dimensions/model and availability before choosing versions.

Completion check: a known query for each of the fifteen role IDs returns only matching role context with the source title and version. Missing roles produce an explicit not-found result.

## Workflow 2 Internship Career Tools

`MCP Server Trigger → three selected tools`

Production path suggestion: `internship-career-tools`. Use header or bearer authentication, stored in n8n credentials. Copy the actual published production URL from the new account; never invent a URL or use its test URL in the deployed application.

| Tool | Input | Output |
| --- | --- | --- |
| search_internship_roles | Search text containing the authoritative company and role ID. | Matching role facts and source references; no unrelated role fallback. |
| days_until | An ISO date, using the application's configured timezone/current date. | Validated deadline, signed day difference and expired/open state. |
| word_count | Exact plain-text letter. | Word count, rule/version used, and a digest identifying the counted text. |

Define consistent schemas and helpful validation errors. Count the exact final candidate letter, not a previous draft or a model's paraphrase. Use one documented word-count rule in n8n, Python validation and frontend display.

The role tool gets read-only access to knowledge data. These tools cannot insert applications, read arbitrary users' resumes, send mail or execute arbitrary URLs. Configure each agent's MCP Client Tool with only its required tools selected.

n8n's MCP Server Trigger exposes tools and supports authenticated production endpoints. [MCP Server Trigger documentation](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-langchain.mcptrigger/).

Completion checks: independently call all three tools; test invalid dates, empty text, unknown role and incorrect credentials. Inspect actual MCP executions before adding agent orchestration.

## Workflow 3 Internship Coach API

Input from the Python worker:

```json
{
  "analysis_id": "opaque-analysis-id",
  "request_id": "stable-request-id",
  "company": "NVIDIA",
  "role_id": "NVIDIA-01",
  "candidate_name": "Visitor's signature name",
  "resume_text": "Text extracted from this request's uploaded resume",
  "current_date": "2026-10-30",
  "timezone": "Asia/Kolkata",
  "catalog_version": "version-from-database"
}
```

Proposed main flow:

`Authenticated POST Webhook → Validate input → Sanitize personal data → Scope/safety guardrail → Role Matcher → Letter Writer → Letter Critic → Validate result → Respond to Webhook`

Three distinct model roles, with explicit input/output between stages:

1. **Role Matcher:** retrieve the selected role using MCP and explain the resume's relevant evidence, genuine gaps, source and deadline. Use role search and days_until. Do not infer suitability from protected characteristics.
2. **Letter Writer:** produce a concise, specific letter from the sanitized resume evidence and retrieved role. No tools are needed in this writing stage. Do not invent skills, contact details, employers or achievements.
3. **Letter Critic:** check relevance, unsupported claims, fairness, placeholders and length; use MCP word_count on the exact candidate text. Return a structured review and the final candidate text.

Use the smallest suitable n8n AI node for each stage; a plain writing stage need not be presented as a tool-using agent. Verify available node versions in the new account before producing importable JSON.

Avoid an additional supervisor repeatedly re-reading and re-dispatching all three stages. At least one actual agent must choose its tools to preserve the challenge's agent-loop requirement. Bound agent iterations and permit at most one explicit revision pass; when a revision changes the letter, recount and review that exact version. A validation failure returns a controlled error rather than starting an open-ended rewrite loop.

Do not assert that a model definitely called a tool because its prompt told it to. Capture and validate structured tool execution evidence. If required role retrieval/counting is missing, report the failed stage clearly. Prove the trace format in a small tool test before adding any strict validator—the old workflows failed partly because validators assumed evidence that was absent or differently shaped.

Sanitize emails, phone numbers and addresses before they reach model prompts. Keep the signature name separate from matching; Python can insert it into the final template if needed. Treat instructions embedded in resume text as untrusted document content. Keep a real Guardrails node and provide a demonstrable blocked case. Do not redact all evidence useful for matching.

Successful response to Python:

```json
{
  "analysis_id": "opaque-analysis-id",
  "request_id": "stable-request-id",
  "company": "NVIDIA",
  "role_id": "NVIDIA-01",
  "status": "ready",
  "final_letter": "Plain-text candidate letter without Markdown fences",
  "match_report": { "strengths": [], "gaps": [], "sources": [] },
  "deadline_info": { "deadline": "2026-12-25", "days_remaining": 56 },
  "critic_review": { "passed": true, "feedback": [], "word_count": 180 },
  "tool_evidence": [],
  "approval_allowed": true
}
```

The date/count values above illustrate the schema, not an executed result. Validate actual values and bind all evidence to the same analysis and text digest. Python adapts this response into the frontend's existing `status/result` envelope and adds a draft version.

Expected failure envelope: `analysis_id`, `request_id`, `status: failed`, safe `error_code`, failed `stage` and actionable `message`. Return appropriate HTTP status codes for bad inputs/authentication. Unhandled execution errors or network timeouts are still handled by the Python worker; the Error Monitor is not a substitute for a response or job timeout.

Completion checks: all roles, two different resumes, missing role, unsupported requests, personal-data masking, malicious document instructions, malformed model JSON, bounded revision and model timeout. Measure model calls/tokens and total time honestly. Ten seconds is a target to benchmark, not a guaranteed result.

n8n distinguishes test and published production webhooks and supports header authentication. [Webhook documentation](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/).

## Workflow 4 Internship Error Monitor

`Error Trigger → Extract safe metadata → Operational log`

Capture execution ID, workflow, failed node, timestamp and a safe error category. Do not copy resume text, generated letters, credentials or full sensitive node payloads into operational logs. Start without email/Slack notifications; adding messages requires explicit authorization.

Link this as the error workflow for automatic executions. It does not run for manual test errors, does not repair failed jobs automatically, and does not hold a browser request open. Python remains responsible for marking jobs failed and exposing retries. [Error Trigger documentation](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.errortrigger/).

## Human approval and original assignment differences

The original challenge explicitly requested Simple Vector Store with a memory key, an n8n approval form and a Data Table. The newer web application requirement uses persistent PostgreSQL retrieval and website approval enforced by Python. These are deliberate changes, not exact compliance with every original node requirement. If that exact classroom submission is still required, maintain a separate demonstrable course version or obtain the instructor's acceptance of the replacements before claiming equivalence.

Preserve the substantive safety rule: a generated draft is not an approved application. Only an explicit website decision can authorize Python's transaction to save the final application. Operational records and queued uploads must exist before that decision so processing can survive restarts; they are separate from the approved tracker.

## Build order

1. The user creates/signs into the intended fresh n8n account. Establish its available node versions and credentials without pasting secrets into chat or Git.
2. Provision the development PostgreSQL database and apply the knowledge/catalog schema. This dependency must exist before claiming persistent indexing works.
3. Build Workflow 1 and prove indexing and role retrieval with all expected IDs.
4. Build Workflow 2; verify each tool directly before agents use it.
5. Build Workflow 3 incrementally: input validation, one agent/tool, then writing, criticism and response validation. Test through its webhook.
6. Add Workflow 4 and test an automatic controlled failure.
7. Connect the Python worker and existing frontend; verify separate-user ownership, approval/rejection and exact-letter export.

Keep existing account workflows untouched. The next action after approving this plan is account/workspace setup and the PostgreSQL prerequisite, not importing another untested large workflow.
