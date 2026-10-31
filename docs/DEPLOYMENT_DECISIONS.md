# Deployment and repository access decisions

Updated 31 October 2026, Asia/Kolkata.

**Version 1 checkpoint:** the user authorized publishing all current source progress to GitHub. Supabase exists in Mumbai, and its migrations/configuration are included in the repository. Python runtime credentials, n8n integration and Cloudflare/Render deployment are still pending. The earlier local-only instruction described below has been superseded for source publishing. It remains separate from authorization to deploy the application.

## Selected hosts

- Frontend: Cloudflare, using Pages for the existing static frontend.
- Python FastAPI backend: Render web service.
- Python queue consumer: a separate Render background worker or a subsequently verified Render-managed execution option.
- Database and persistent queue: Supabase PostgreSQL, with pgvector for role retrieval and Supabase Queues/pgmq as the proposed queue transport.
- AI pipeline and MCP tools: the intended new n8n account.

These are deployment choices, not live provisioned services. No paid resource, public deployment, GitHub branch or push was created by this access check.

## GitHub access check

Repository: https://github.com/eshananduri-arch/ai-internship-application-coach

The GitHub connector identifies the authenticated user as Zeeshan1786. Repository metadata reports pull=true and push=true, with admin=false and maintain=false. A native Git push dry run to a new codex/access-check-20261031 branch returned success. The --dry-run flag prevented branch creation and upload.

The connector's separate collaborator-permission endpoint returned HTTP 403 Resource not accessible by integration. That limits this integration's detailed permission inspection; it does not contradict the repository's push=true metadata or the successful native Git check. An actual connector file-write operation was not performed or tested. Protected branches may still require a pull request and checks.

At the time of the access check, implementation was to remain local. The later version 1 instruction authorizes the current source push; public application deployment remains deferred until after integration and testing.

## Frontend to API routing

The existing frontend uses /api and same-origin cookie requests. Cloudflare and Render default hostnames are different origins; publishing both without a routing change would not preserve that contract.

Proposed approach: add a narrow Cloudflare Pages Function or Worker that forwards only /api/* to the configured Render service. Keep browser requests on the frontend origin, preserve approved session/cookie and CSRF behavior, and configure the backend's trusted external origin explicitly. Treat forwarded headers as untrusted unless authenticated/validated by the gateway. Do not create an arbitrary-target proxy or expose database/n8n credentials in frontend assets.

Route validation, upload/body limits, Set-Cookie handling, no-store private responses and export streaming must be tested end to end. Local development can continue using its same-origin dev setup. Publish only intended frontend assets; tests, tools and development fixtures do not need to be served publicly.

## Queues and dynamic management on Render

Maintain the two agreed backend upgrades: durable accepted jobs and a global dynamic processing manager. The initial global cap is two generation jobs, adjustable within provider and budget constraints after load testing. Changing active concurrency is distinct from changing Render instance count or billing.

Render background workers are continuously running services that can poll the queue. Their service type does not offer a Free instance under the documented free-service choices. Render's native service autoscaling currently requires a Pro workspace or higher and uses CPU/memory targets; it does not automatically react to PostgreSQL backlog. A free web service can sleep and must not be treated as a reliable always-on queue worker.

Choose and review the relevant Render compute/workspace costs before provisioning. If scale-to-zero is required for cost savings, verify the chosen Render execution product and a reliable external wake/reconciliation path before implementing it. A stopped polling worker cannot wake itself. Do not claim dynamic threads alone lower a fixed hosting bill.

## Planned deployment files

```text
frontend/functions/api/[[path]].js    narrow proxy if Pages Functions selected
frontend build/publish configuration intended static assets only
backend/Dockerfile                  shared API/worker image
render.yaml                         reviewed Render service definitions
.github/workflows/ci.yml             test checks before releases
docs/deployment.md                  final runbook after live setup
```

These files are planned, not generated or deployed by this access check. Final proxy placement follows the configured Cloudflare project root. render.yaml must not contain real secret values.

## References

- [Cloudflare Pages monorepos](https://developers.cloudflare.com/pages/configuration/monorepos/)
- [Render background workers](https://render.com/docs/background-workers)
- [Render scaling](https://render.com/docs/scaling)
- [Render free service limits](https://render.com/docs/free)

The Word guide predates these provider choices and the dynamic-worker extension. This record and WORKER_MANAGEMENT_PLAN.md carry those newer decisions until the guide is revised.
