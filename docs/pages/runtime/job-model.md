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

`dead-letter` is not defined here as a base lifecycle state. It is treated as a
later extension boundary that may be reached from failure or retry exhaustion,
but its detailed recovery semantics are defined elsewhere.

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

- retry policy, backoff, jitter, or escalation rules
- fairness, starvation prevention, or backpressure policy
- dead-letter recovery behavior such as replay or discard rules
- bulk-operation semantics beyond acknowledging that bulk actions operate on the
  same lifecycle states

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
  state: :queued,
  created_at: created_at
)

job.can_transition_to?(:reserved)
# => true

reserved_job = job.transition_to(:reserved, updated_at: Time.utc(2026, 3, 26, 12, 0, 5))
reserved_job.state
# => :reserved
```

Lifecycle extensions are also explicit. Follow-on runtime work can register a
new state and link it to the base lifecycle without redefining the canonical
states. Extension state names are normalized to lowercase snake case and must
fit within 64 characters:

```ruby
Karya::JobLifecycle.register_state(:dead_letter, terminal: true)
Karya::JobLifecycle.register_transition(from: :retry_pending, to: :dead_letter)
```

## Related Concepts

- [Workers](/runtime/workers/): see how jobs are reserved and executed
- [Controls](/runtime/controls/): inspect and intervene in runtime state
- [Retries](/reliability/retries/): understand how failed jobs re-enter the
  runtime
- [Workflow Basics](/workflows/basics/): see when a single job becomes a
  workflow
