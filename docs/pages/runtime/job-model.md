---
title: Job Model
parent: Runtime
nav_order: 1
permalink: /runtime/job-model/
---

# Job Model

Jobs are the canonical executable unit in Karya. The job model anchors queueing,
worker execution, retry behavior, workflow composition, and operator
inspection.

## Canonical Job Shape

The canonical model distinguishes between the application-defined job, the
queued job instance, the reservation used to start work, and the terminal
outcome recorded for operators and automation.

A canonical job instance carries these behavior-level expectations:

- stable job identity for the queued instance being tracked by the runtime
- queue assignment that determines where the job becomes available
- executable payload boundaries that identify the work to run without treating
  queue metadata as application input
- lifecycle metadata that callers, workers, and operator surfaces can inspect
  consistently
- one canonical current state for the job instance at any point in time
- optional scheduling metadata such as `priority`, `concurrency_key`, and
  `rate_limit_key` for runtime backpressure decisions
- optional execution timing metadata such as `execution_timeout` and
  `expires_at` for worker-side time bounds and queue-side expiration guards
- optional retry metadata such as `retry_policy` and `next_retry_at` for
  bounded retry scheduling
- optional failure metadata such as `failure_classification` for operator and
  retry decisions

Application code defines what the job does. Karya owns the queue placement,
lifecycle, reservation, execution, and operator-visible state around that work.

## Core Expectations

- a job has an explicit lifecycle rather than an implicit fire-and-forget state
- queues determine where work is routed
- workers reserve jobs according to the runtime and reliability contracts
- operators can inspect job state through UI, API, and CLI surfaces

## Lifecycle States

The base lifecycle vocabulary for queued job instances is:

| State           | Meaning                                                                                       | Allowed next transitions           |
| --------------- | --------------------------------------------------------------------------------------------- | ---------------------------------- |
| `submission`    | the runtime is accepting or validating enqueue intent                                         | `queued`                           |
| `queued`        | the job is durably available for reservation on its assigned queue                            | `reserved`, `cancelled`            |
| `reserved`      | one worker has an exclusive, temporary claim on the job                                       | `running`, `queued`, `cancelled`   |
| `running`       | execution has started from a valid reservation                                                | `succeeded`, `failed`, `cancelled` |
| `succeeded`     | execution completed successfully                                                              | terminal state                     |
| `failed`        | execution ended unsuccessfully for the current attempt                                        | `retry_pending`                    |
| `retry_pending` | the job remains in the lifecycle and is waiting to re-enter queue execution under retry rules | `queued`, `cancelled`              |
| `cancelled`     | execution will not continue because the runtime or operator stopped the job                   | terminal state                     |

`dead_letter` is not defined here as a base lifecycle state. It is treated as a
later extension boundary that may be reached from failure or retry exhaustion.
The reliability docs describe that isolation and recovery layer alongside the
canonical lifecycle that dead-letter handling extends.

`retry_pending` is the base-lifecycle extension point where later dead-letter
behavior can attach. The table above lists only concrete base-state transitions
implemented by the canonical lifecycle.

## Lifecycle Invariants

- one queued job instance has one canonical current state at a time
- reservation is exclusive and temporary rather than a second execution state
- execution starts only from a valid reservation
- `succeeded` and `cancelled` are distinct terminal outcomes
- `failed` records the result of an execution attempt, while `retry_pending`
  keeps the same job instance in the lifecycle for later requeue
- retries, uniqueness, and operator controls extend this lifecycle instead of
  inventing parallel state models
- completed executions and failed attempts remain operator-visible and
  historically meaningful

## Lifecycle Boundaries

The documented lifecycle covers:

- submission and enqueue
- queued availability and reservation
- active execution
- success, failure, `retry_pending`, or cancellation
- the boundary where later dead-letter behavior may take over

## Non-Goals For This Contract

This page does not define:

- jitter, escalation, or dead-letter policy beyond the base timing and failure
  classification model
- fairness, starvation prevention, or backpressure policy
- dead-letter recovery workflows such as replay or discard rules
- selector, approval, and audit semantics for bulk operator workflows

## Dependency Boundaries

This page is the source of truth for the job lifecycle model used by follow-on
runtime work:

- queueing and reservation behavior extend it
- worker bootstrap and execution flow extend it
- graceful shutdown and drain behavior extend it
- runtime control and inspection APIs extend it
- uniqueness, bulk operations, dead-letter handling, and
  fairness/backpressure extend it

Follow-on work may add detail, but it should not redefine the base lifecycle
states or their core meanings.

## Queueing And Reservation Contract

The first runtime queueing layer keeps the lifecycle explicit:

- `enqueue` accepts only jobs in `submission` and persists them as `queued`
- `reserve` matches queued jobs against worker subscription boundaries rather
  than treating queue membership alone as executability
- `reserve` returns a separate reservation lease token rather than embedding
  lease metadata into the job itself
- reservation leases expire back to `queued` if they are not released or
  consumed before `expires_at`
- worker execution from a valid reservation remains follow-on work rather than
  part of the queueing contract itself

## Why This Matters

Downstream features such as uniqueness, bulk operations, workflow steps,
approval checkpoints, and governed actions all rely on a stable job model.

## Common Scenarios

### Defining Application Work

Use a job as the smallest durable unit of application work:

```ruby
module BillingJob
  def self.perform(account_id:, amount_cents:)
    # Application work runs here.
  end
end
```

Application code defines executable work, and Karya owns the routing,
lifecycle, reservation, and operator-visible state around it.

### Working With The Canonical Job API

`Karya::Job` is the immutable value object for a queued job instance. It
normalizes identifiers, deeply freezes arguments, and enforces the canonical
lifecycle through `Karya::JobLifecycle`.

```ruby
created_at = Time.utc(2026, 3, 26, 12, 0, 0)

job = Karya::Job.new(
  id: 'billing-123',
  queue: 'billing',
  handler: 'billing_sync',
  arguments: { account_id: 42, source: 'dashboard' },
  priority: 10,
  concurrency_key: 'account-42',
  rate_limit_key: 'partner-api',
  state: :queued,
  created_at: created_at
)

job.can_transition_to?(:reserved)
# => true

reserved_job = job.transition_to(:reserved, updated_at: Time.utc(2026, 3, 26, 12, 0, 5))
reserved_job.state
# => :reserved
```

`priority` defaults to `0`. Higher numbers win within same queue, while worker
subscription queue order still decides which queue is scanned first.
`concurrency_key` and `rate_limit_key` are optional identifiers that let queue
stores apply configured backpressure policies without mutating handler input.
`retry_policy` is an optional deterministic retry/backoff definition, while
`next_retry_at` marks when a `retry_pending` job becomes eligible to return to
`queued`. `execution_timeout` is an optional per-job execution cap in seconds.
`expires_at` is an optional absolute boundary after which queued or
`retry_pending` work fails as expired instead of continuing toward execution.
`failure_classification` is optional operator-visible metadata set by the
runtime to one of `:error`, `:timeout`, or `:expired`.

Lifecycle extensions are also explicit. Follow-on runtime work can register a
new state and link it to the base lifecycle without redefining the canonical
states. Extension state names are normalized to lowercase snake case, stored on
`Karya::Job` instances as `String`s, and must fit within 64 characters.
Canonical lifecycle states remain `Symbol`s. When comparing states, normalize
both values through `Karya::JobLifecycle.normalize_state` so string-backed
extension states and symbol-backed canonical states follow the same rules:

```ruby
dead_letter_state = Karya::JobLifecycle.register_state(:dead_letter, terminal: true)
Karya::JobLifecycle.register_transition(from: :retry_pending, to: dead_letter_state)

job = Karya::Job.new(
  id: 'billing-123',
  queue: 'billing',
  handler: 'billing_sync',
  arguments: { account_id: 42, source: 'dashboard' },
  state: :retry_pending,
  created_at: Time.utc(2026, 3, 26, 12, 0, 0)
)

dead_letter_job = job.transition_to(dead_letter_state, updated_at: Time.utc(2026, 3, 26, 12, 5, 0))
dead_letter_job.state
# => "dead_letter"

Karya::JobLifecycle.normalize_state(dead_letter_job.state) ==
  Karya::JobLifecycle.normalize_state(dead_letter_state)
# => true

Karya::JobLifecycle.validate_state!(dead_letter_job.state)
# => "dead_letter"
```

## Related Concepts

- [Workers](/runtime/workers/): see how jobs are reserved and executed
- [Controls](/runtime/controls/): inspect and intervene in runtime state
- [Retries](/reliability/retries/): understand how failed jobs re-enter the
  runtime
- [Dead Letters](/reliability/dead-letters/): see how isolation extends the
  base lifecycle after bounded retry
- [Workflow Basics](/workflows/basics/): see when a single job becomes a
  workflow
