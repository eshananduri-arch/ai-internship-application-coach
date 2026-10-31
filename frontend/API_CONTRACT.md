# Python API contract for PostgreSQL integration

This is the contract expected by the frontend, not an existing server. All paths use the same origin and `/api` prefix. Responses are JSON except downloads. Errors use an appropriate HTTP status and `{ "message": "A safe, actionable error" }`. Do not expose stack traces, model secrets or resume text in errors.

## Anonymous ownership

`GET /api/session` creates or resumes an anonymous server session and returns `{ "csrf_token": "..." }`. Set an opaque session cookie with HttpOnly, Secure in production, SameSite=Lax, Path=/ and an intentional expiry. Keep the session secret out of JavaScript. Frontend POST requests include `X-CSRF-Token`; validate it and Origin server-side.

Every analysis, application, decision and download must be authorized by the current session. Return 404 for other sessions' IDs. Use cryptographically random public IDs and never treat those IDs as sufficient authorization. No cross-session listing is allowed.

## Public catalog

`GET /api/companies`

```json
[{ "name": "NVIDIA" }]
```

`GET /api/roles?company=NVIDIA`

```json
[{ "company": "NVIDIA", "role_id": "NVIDIA-01", "role": "AI/ML Intern", "location": "Bengaluru", "deadline": "2026-12-25" }]
```

Use the authoritative catalog and reject invalid company/role combinations at submission. The local catalog contains fictional educational listings, not verified live vacancies.

## Generate

`POST /api/analyses` accepts multipart fields:

- `resume`: exactly one PDF or DOCX, non-empty, at most 5 MB.
- `request_id`: a client UUID, used for correlation/idempotency, never authorization.
- `candidate_name`, `company`, `role_id`, `role_title`.

The header `Idempotency-Key` equals the request UUID. Scope it to session and payload so double submissions do not duplicate jobs. Inspect actual file signatures, reject malformed/unsupported content and oversized or dangerous DOCX archives, extract text, then run the pipeline with this upload's text. Never substitute a previous user's resume or a hardcoded testing resume.

Return promptly with HTTP 202:

```json
{ "analysis_id": "opaque-analysis-id", "status": "queued", "stage": "Reading your resume" }
```

`GET /api/analyses/{analysis_id}` returns queued/processing, failed, or ready. The frontend polls every 1.5 seconds for up to three minutes per check cycle. Use `Cache-Control: no-store`. A failed response can be `{ "status": "failed", "message": "The model is unavailable. Please try again." }`.

Ready response (also accepted directly from the original POST):

```json
{
  "analysis_id": "opaque-analysis-id",
  "status": "ready",
  "result": {
    "company": "NVIDIA",
    "role_id": "NVIDIA-01",
    "final_letter": "Dear Hiring Team,\n\nActual generated letter...\n\nSincerely,\nCandidate Name",
    "draft_version": 1,
    "approval_allowed": true,
    "critic_review": { "feedback": [] }
  }
}
```

Return plain text without Markdown fences. The pipeline should use the resume's verified experience, retrieved role requirements and current dates. It must not invent qualifications, addresses, contact details or employment claims. Supply a complete salutation, focused paragraphs and signature, with no placeholders. Backend review must enforce its own content rules; browser checks are only usability checks.

## Human decision

`POST /api/analyses/{analysis_id}/decision`, with CSRF and Idempotency-Key headers:

```json
{ "decision": "approve", "final_letter": "Exact user-approved text", "draft_version": 1 }
```

Validate ownership, current draft version, letter length, placeholders, and any mandatory assignment/pipeline checks. Revalidate edited text. In a PostgreSQL transaction persist the exact approved wording and an approval timestamp; return only after commit:

```json
{ "status": "approved", "application_id": "opaque-application-id", "final_letter": "Exact user-approved text" }
```

For `decision: "reject"`, invalidate that draft and return `{ "status": "rejected" }`. Do not create an approved application or send anything. An analysis and any audit records are separate from a saved approved application; define resume retention and cleanup explicitly. Repeated requests with the same idempotency key must return the same outcome. Reject reuse of the key for different content and reject conflicting decisions for a finalized analysis.

Approval means save and enable download. This frontend does not send an email or apply to an employer.

## Downloads

`GET /api/applications/{application_id}/download?format=docx|pdf|txt`

Authorize session ownership and approved state. Export the immutable approved text. Respond with the correct MIME type, safe Content-Disposition attachment filename, and no-store:

| Format | Content-Type |
| --- | --- |
| DOCX | application/vnd.openxmlformats-officedocument.wordprocessingml.document |
| PDF | application/pdf |
| TXT | text/plain; charset=utf-8 |

Generate genuine DOCX/PDF bytes, with justified body paragraphs and left-aligned salutation/signature. Preserve paragraph breaks and approved wording. Do not return an HTML error under a successful status. The frontend rejects an unexpected MIME type.

## PostgreSQL responsibilities

Use migrations for sessions, analyses and approved applications. Every private row needs an ownership relationship. Store approval decisions and draft versions transactionally; use uniqueness constraints for idempotency. Store extracted text only as long as required and avoid retaining original resume binaries by default. Keep secrets in server environment variables. Limit uploads, job concurrency, and generation rate per session/IP. Test two independent sessions against all private routes before deployment.
