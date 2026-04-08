---
title: Workers
parent: Runtime
nav_order: 2
permalink: /runtime/workers/
---

# Workers

Workers are responsible for reserving work, executing jobs, and participating in
coordinated runtime lifecycle behavior.

## Worker Responsibilities

- subscribe to the correct queues
- reserve jobs without violating routing and fairness rules
- move jobs from `queued` to `reserved` and then into `running` only through
  valid lifecycle transitions
- execute work while respecting timeouts, expirations, and cancellation
- participate in graceful shutdown and drain behavior

## Supervision And Lifecycle

Karya documents worker behavior around:

- bootstrap and execution flow
- drain-safe shutdown
- pause and resume interactions with queue state
- runtime supervision hooks used by operators and automation

Workers extend the canonical job lifecycle; they do not introduce a separate
execution state model.

The runtime uses a supervisor-owned process model. `karya worker` starts a
supervisor process that maintains the configured number of child worker
processes, and each child process executes the queue loop through a thread
pool. Process-level concurrency is controlled independently from per-child
thread concurrency so operators can shape worker topology for the selected
queue store and handler workload.

When the supervisor receives `SIGINT` or `SIGTERM`, it enters drain mode: it
stops replacing child workers, signals active children to stop polling, and
waits for in-flight execution to finish. If a child has reserved a job but has
not started execution yet, that reservation is released back to `queued`. A
repeated shutdown signal escalates to forced termination of any remaining
children.

## Operator View

Worker state is surfaced consistently through:

- dashboard worker views
- operator APIs
- CLI-oriented control and inspection commands

## Common Scenarios

### Executing Reserved Work

Workers are the runtime-side executors for queued work:

```ruby
store = Karya::QueueStore::InMemory.new
Karya.configure_queue_store(store)

class BillingJob
  def self.call(**)
  end
end

Karya::CLI.start([
  'worker',
  'billing',
  '--processes',
  '1',
  '--threads',
  '1',
  '--state-file',
  '/tmp/karya-runtime-billing.json',
  '--env-prefix',
  'billing_worker',
  '--worker-id',
  'worker-1',
  '--handler',
  'billing_sync=BillingJob'
])
```

The supervisor coordinates shutdown and control signals, while child worker
threads reserve work, execute it, and drain in-flight jobs when shutdown
begins. Per-worker env overrides use `KARYA_<PREFIX>_PROCESSES` and
`KARYA_<PREFIX>_THREADS`, for example
`KARYA_BILLING_WORKER_PROCESSES` and `KARYA_BILLING_WORKER_THREADS`.
Use multiple processes or threads only with a queue store that is safe to
share across processes and thread-safe handlers.
`Karya::QueueStore::InMemory` is single-process and is shown here only for local
examples.

`Karya.configure_logger` and `Karya.configure_instrumenter` define process-wide
defaults. If a process hosts multiple runtimes, inject explicit `logger:` and
`instrumenter:` collaborators to avoid cross-runtime global mutation.

## Related Concepts

- [Job Model](/runtime/job-model/): worker behavior starts from the job lifecycle
- [Controls](/runtime/controls/): operators supervise workers through shared surfaces
- [Backpressure](/reliability/backpressure/): rate limits and queue pressure
  shape worker behavior
- [Dashboard](/operator/dashboard/): worker state must stay visible to
  operators
