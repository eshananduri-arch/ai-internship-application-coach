# Dynamic worker and queue management

Requirement added 30 October 2026. This extends the project design; no queue, backend worker, autoscaler or management dashboard has been deployed.

## Objective

Keep accepted application requests durable, adjust simultaneous processing to demand, respect model/n8n/database limits, and avoid unnecessary idle compute. Every accepted request must reach an explicit ready, rejected, cancelled or failed state. Never silently drop queued requests.

## Components

- Supabase PostgreSQL holds analysis state and durable job metadata. Use Supabase Queues/pgmq as the proposed message transport, with messages containing only a job ID rather than resume contents. Job records and queue messages must be published transactionally. Validate extension availability before implementation.
- Python workers extract files and call n8n under a global concurrency limit. Use asynchronous network clients for I/O, bounded threads for suitable blocking library calls and processes for expensive CPU-bound work when measurement justifies them.
- A small controller in the backend manages processing capacity. It examines backlog, oldest waiting job, recent processing times, worker heartbeats, rate-limit responses, database connection availability and configured cost limits.
- A private management interface exposes aggregate operations data and authorized controls. It is separate from the public no-login application and requires administrator authentication and authorization. Do not expose private resumes or letters on a shared operations screen.

## Initial dynamic policy

Start with a configurable global cap of two generation jobs, not two per process. Allow one job when demand is low and two when backlog and provider capacity justify it. Raise the cap only after simultaneous-user testing and quota verification.

When no jobs need processing, there are zero active generation tasks. This does not by itself mean zero running servers or zero hosting cost. Release unused resources, back off idle polling and drain excess workers rather than cancelling active generation. Use cooldowns and sustained observations so short bursts do not repeatedly start and stop workers.

Enforce shared capacity with database-backed slot leases or another atomic global coordinator; an in-process semaphore alone does not enforce a limit across replicas. Give each worker/slot a lease and heartbeat. Expired leases recover after failures; stale workers cannot commit results over a newer attempt.

Provider constraints take precedence over backlog. On rate-limit responses honor retry guidance and back off. Bound model requests/tokens per time window, total concurrent n8n executions, database connections and generation attempts. Stop admitting new processing above configured budgets while preserving queued work and showing a clear status. Any estimated token cost must be labelled as an estimate until provider usage is reconciled.

## Real hosting autoscaling

Thread count, active jobs and hosting instances are different controls. A fixed-price server may cost the same with one thread or ten. To save idle instance cost, select hosting with suitable metering and worker scaling, and implement a reliable wake-up path.

A polling worker cannot wake itself after all its instances are stopped. Scaling to zero therefore requires an external dispatcher, authenticated queue notification, scheduler or managed queue consumer. A newly accepted job must trigger that path; a periodic reconciliation must also recover missed wakeups. Never assume a hosting autoscaler automatically inspects a PostgreSQL queue.

Until the hosting provider and wake mechanism are selected and tested, keep a minimal worker available with bounded, backed-off polling. Do not claim scale-to-zero has been implemented. Scaling down must let active jobs finish or safely return their leases for recovery.

The API can scale independently of the worker. Maintaining responsive status/approval endpoints should not require starting an unbounded number of model calls. Expect cold-start delay where instances are allowed to stop.

## Cost controls

Concurrency improves throughput; it does not make a single external model call inherently faster or reduce the number of letters users request. Control AI spending through compact prompts, relevant retrieved context, bounded revision loops, token limits, request deduplication and safe retries. Avoid shared caches containing private resume output.

Also account for database, n8n, model and storage charges separately. Worker scaling cannot eliminate those charges. Track model calls and tokens per completed analysis, retry amplification and failed-job spending.

## Private management capabilities

Display queued/active/completed/failed counts, oldest wait, processing latency, worker health, model throttles and usage estimates. Controls may change the allowed processing cap within a hard maximum, pause admission of new processing, resume it and request a deduplicated retry of an eligible failed job.

Use an existing protected Supabase dashboard for initial database/queue inspection where practical. A custom administrator UI can follow once the worker is implemented; it must not be accessible through the anonymous visitor session. Audit administrator changes without storing resume text. No automatic email/Slack notification is authorized by this requirement.

## Planned files and records

```text
backend/app/services/jobs.py
backend/app/services/worker_manager.py
backend/app/services/rate_limits.py
backend/app/services/usage.py
backend/app/api/operations.py
backend/app/worker.py
backend/tests/integration/test_queue_recovery.py
backend/tests/integration/test_global_concurrency.py
backend/tests/integration/test_operations_access.py
supabase/migrations/<timestamp>_queue_and_worker_leases.sql
docs/operations.md
```

Keep the existing analyses/job records as the state source of truth. Add worker/slot leases, management settings, safe operational events and usage measurements as needed. Do not create unrelated competing job state machines. Treat delivery as repeatable: acknowledge/archive a message only after its outcome is committed, and deduplicate side effects on redelivery.

## Acceptance checks

Submit ten independent requests and confirm every accepted job has a durable ID and visible outcome. Verify the global processing cap across multiple worker processes. Test duplicate delivery, worker death during an n8n call, stale results, visibility/lease expiry, missed wakeups, throttling and safe retries. Test idle downscaling followed by a fresh request. Compare billed/estimated usage against a fixed-capacity baseline before claiming cost savings. Verify anonymous users cannot access operations endpoints or other visitors' data.

## References

- [Supabase Queues](https://supabase.com/docs/guides/queues)
- [Python concurrent execution tools](https://docs.python.org/3/library/concurrent.futures.html)
- [Cloud Run autoscaling as an example of request-driven instance scaling](https://docs.cloud.google.com/run/docs/about-instance-autoscaling)

Cloud Run is an example, not a selected deployment provider. The Word project guide predates this extension and will need the new worker-management files and flow added in its next revision.
