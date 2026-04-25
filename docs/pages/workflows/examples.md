---
title: Examples
parent: Workflows
nav_order: 6
permalink: /workflows/examples/
---

# Workflow Examples

These examples show how workflow definitions, immutable batches, dependency
gating, snapshots, rollback, and recovery controls fit together from developer
and operator perspectives.

## Invoice Closeout

An invoice closeout workflow usually has independent preparation, a payment
chain, and a final fan-in step:

```ruby
workflow = Karya::Workflow.define(:invoice_closeout) do
  step :calculate_totals, handler: :calculate_totals
  step :capture_payment,
       handler: :capture_payment,
       depends_on: :calculate_totals,
       compensate_with: :refund_payment
  step :write_ledger,
       handler: :write_ledger,
       depends_on: :calculate_totals,
       compensate_with: :reverse_ledger
  step :emit_receipt,
       handler: :emit_receipt,
       depends_on: %i[capture_payment write_ledger]
end
```

At enqueue time, each step is bound to one concrete job. Karya stores those
primary jobs in one immutable workflow batch:

```ruby
store.enqueue_workflow(
  definition: workflow,
  batch_id: :invoice_closeout_123,
  jobs_by_step_id: {
    calculate_totals: calculate_totals_job,
    capture_payment: capture_payment_job,
    write_ledger: write_ledger_job,
    emit_receipt: emit_receipt_job
  },
  compensation_jobs_by_step_id: {
    capture_payment: refund_payment_job,
    write_ledger: reverse_ledger_job
  },
  now: Time.now
)
```

Workers still reserve ordinary jobs. Workflow metadata only decides whether a
queued step is ready:

- `calculate_totals` is eligible immediately
- `capture_payment` and `write_ledger` wait for `calculate_totals`
- `emit_receipt` waits for both payment capture and ledger write

Operators can inspect the current run without reading queue-store internals:

```ruby
# After calculate_totals and capture_payment have succeeded, write_ledger is
# still queued and emit_receipt is waiting on both fan-in prerequisites.
snapshot = store.workflow_snapshot(batch_id: :invoice_closeout_123, now: Time.now)

snapshot.state
#=> :blocked

snapshot.fetch_step(:emit_receipt).prerequisite_states
#=> {"job-capture_payment" => :succeeded, "job-write_ledger" => :queued}

snapshot.fetch_step(:emit_receipt).blocked?
#=> true
```

## Recovery

Workflow replay and retry controls target explicit step ids. They do not infer
targets from workflow state, create a new workflow run, or append to the
primary batch.

```ruby
store.retry_workflow_steps(
  batch_id: :invoice_closeout_123,
  step_ids: [:capture_payment],
  now: Time.now
)
```

Retry moves eligible failed or retry-pending primary step jobs back into normal
queued execution. A dependent step remains blocked until the recovered
prerequisite job actually succeeds.

Dead-letter recovery follows the same explicit boundary:

```ruby
store.replay_workflow_steps(
  batch_id: :invoice_closeout_123,
  step_ids: [:capture_payment],
  now: Time.now
)
```

Replay moves a dead-lettered primary step job back to `queued`. Controlled
retry moves it to `retry_pending` for a supplied retry time, and discard moves
it to `cancelled`:

```ruby
store.retry_dead_letter_workflow_steps(
  batch_id: :invoice_closeout_123,
  step_ids: [:capture_payment],
  now: Time.now,
  next_retry_at: Time.now + 300
)

store.discard_workflow_steps(
  batch_id: :invoice_closeout_123,
  step_ids: [:capture_payment],
  now: Time.now
)
```

Use `workflow_snapshot` after each action. It shows whether the workflow is
still `failed`, `blocked`, `running`, or ready for the next operator decision.

## Rollback

Rollback is explicit. Karya does not automatically roll back a failed workflow.
An operator can request rollback only after the workflow snapshot is `:failed`
and there are no active or dependency-ready queued step jobs left to run. Once
that precondition holds, Karya enqueues compensation jobs only for succeeded
primary steps that declared compensation:

```ruby
store.rollback_workflow(
  batch_id: :invoice_closeout_123,
  now: Time.now,
  reason: 'payment provider settlement failed'
)
```

Compensation runs in reverse workflow definition order. For the invoice
closeout example, `reverse_ledger` reserves before `refund_payment` when both
primary steps succeeded.

Rollback jobs live in a separate immutable rollback batch:

```ruby
snapshot = store.workflow_snapshot(batch_id: :invoice_closeout_123, now: Time.now)

snapshot.rollback_requested?
#=> true

snapshot.rollback.rollback_batch_id
#=> "opaque rollback batch id"

store.batch_snapshot(batch_id: snapshot.rollback.rollback_batch_id, now: Time.now).job_ids
#=> ["rollback-job-write_ledger", "rollback-job-capture_payment"]
```

If every succeeded step is uncompensated, rollback still records the operator
boundary, but there is no physical rollback batch to inspect.

## Operator Inspection

Use the read models together:

- `workflow_snapshot` explains workflow-level state, step state, readiness,
  blocking prerequisites, and rollback metadata
- `snapshot.fetch_step(step_id)` explains one step and the current state of its
  prerequisite jobs
- `batch_snapshot` explains immutable batch membership and aggregate member
  state
- rollback metadata tells operators whether rollback has already been
  requested and which compensation jobs were enqueued

The important distinction is that batch aggregate state describes the member
jobs as a group, while workflow state describes the orchestration meaning of
those jobs.

## Related Concepts

- [Basics](/workflows/basics/): workflow model and state vocabulary
- [Replay](/workflows/replay/): recovery controls and boundaries
- [Controls](/runtime/controls/): runtime entrypoints for operator actions
- [Troubleshooting](/troubleshooting/): symptom-oriented workflow triage
