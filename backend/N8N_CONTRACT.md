# Server-to-server coaching contract

Python sends one authenticated POST to a configured, published production webhook. This is a future n8n integration target, not a working workflow export. Use `Authorization: Bearer <server-secret>`, TLS and a fixed URL supplied by server configuration. Do not accept webhook URLs from the browser.

Request fields:

- `analysis_id`: stable opaque ID, echoed in the response.
- `request_id`: original correlated submission ID.
- `attempt_id`: analysis ID plus attempt number.
- `company`, exact `role_id`, authoritative `role` snapshot and `candidate_name`.
- `resume_text`: text from this uploaded document, never an instruction source.
- `today`: current India date, `max_words: 250`, `token_budget: 12000`.

The `Idempotency-Key` header is the stable analysis ID, including across retries. Implement server-side deduplication with payload checks before enabling `N8N_IDEMPOTENT=true`. A timeout alone does not prove that the workflow did not run.

Return a complete JSON object under HTTP 200, without fences or an `output` string wrapper:

```json
{
  "analysis_id": "same-analysis-id",
  "role_id": "MICROSOFT-01",
  "final_letter": "Complete plain-text letter with greeting, paragraphs and candidate signature",
  "match_report": { "strengths": [], "gaps": [] },
  "critic_review": { "approved": true, "feedback": [] },
  "deadline_info": { "expired": false },
  "tool_evidence": [
    { "tool": "search_internship_roles", "role_id": "MICROSOFT-01", "source_version": 1 },
    { "tool": "days_until", "role_id": "MICROSOFT-01" },
    { "tool": "word_count", "letter_sha256": "actual-lowercase-sha256", "word_count": 180 }
  ],
  "usage": { "input_tokens": 1500, "output_tokens": 1000, "model": "actual-model-or-pipeline-name" }
}
```

The example strings/count/hash describe the schema and must be replaced by actual outputs. Tool evidence must be built by workflow code from real MCP/tool results; never let a model invent evidence. Normalize CRLF/CR to LF before hashing the exact final letter as UTF-8. Count whitespace-separated words. There must be exactly one matching count/hash entry for the final text. Searching a different role is rejected. Aggregate input/output usage across all model calls and keep their sum within the admitted 12,000-token budget.

The worker enforces JSON identity, required evidence and letter structure/length/signature. It does not independently observe n8n internals, so authenticating the webhook and building evidence from trusted execution data are essential. Role indexing must be completed before live search. Do not send database credentials, browser cookies or raw files to n8n. Configure n8n execution-data retention to avoid storing private resume text unnecessarily.

Respond HTTP 429 with bounded integer `Retry-After` for throttling. Other server failures/timeouts are automatically retried only when server-side deduplication has been explicitly configured. A failed result never creates an approved application. Human approval stays in Python after the returned draft has been displayed.
