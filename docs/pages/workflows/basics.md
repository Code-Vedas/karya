---
title: Basics
parent: Workflows
nav_order: 1
permalink: /workflows/basics/
---

# Workflow Basics

Karya workflows build on the core runtime but add durable orchestration,
explicit state transitions, and operator-facing execution history.

## Covered Behavior

- workflow primitives and composition
- chaining, prerequisites, fan-out, and fan-in
- batch identity and aggregate state
- ordered compensation and durable rollback
- workflow state and failure handling

## Common Scenarios

### Coordinating Multi-Step Work

Use a workflow when multiple steps need one durable execution story:

```ruby
workflow = Karya::Workflow.define(:invoice_closeout) do
  step :calculate_totals, handler: :calculate_totals
  step :capture_payment, handler: :capture_payment, depends_on: :calculate_totals
  step :emit_receipt,
       handler: :emit_receipt,
       depends_on: %i[calculate_totals capture_payment]
end
```

This is the core idea: Karya treats related work as one inspectable workflow,
not a pile of unrelated background jobs.

Workflow steps are bound to concrete jobs at enqueue time. Karya stores the
whole run as one immutable batch, then applies prerequisite checks when workers
reserve jobs:

- root steps are eligible immediately
- chained steps wait for their prerequisite job to succeed
- fan-out children become eligible together after their shared parent succeeds
- fan-in steps wait until every prerequisite has succeeded

Failed, cancelled, dead-lettered, retry-pending, reserved, running, and still
queued prerequisite jobs do not unblock dependent steps. Retry can still move a
failed prerequisite back through normal execution; once that prerequisite
succeeds, dependent queued work becomes eligible.

Workflow snapshots expose the current workflow state separately from the batch
aggregate state:

- `pending` when steps are queued and ready but not yet active
- `running` while at least one step is active, or workflow progress has made
  queued follow-up work eligible
- `blocked` when queued dependent steps are waiting on prerequisites
- `succeeded` when every step succeeded
- `cancelled` when every step was cancelled
- `failed` when a step failed, was dead-lettered, or terminal mixed outcomes
  prevent workflow success

Steps can also declare compensation work for explicit saga rollback:

```ruby
workflow = Karya::Workflow.define(:invoice_closeout) do
  step :capture_payment,
       handler: :capture_payment,
       compensate_with: :refund_payment,
       compensation_arguments: { reason: :workflow_rollback }
end
```

Compensation jobs are supplied when the workflow is enqueued, but they are not
members of the primary workflow batch. For workflows with compensable steps,
the caller must provide matching `compensation_jobs_by_step_id` at enqueue
time. Each supplied compensation job must exactly match the step's
`compensate_with` handler and `compensation_arguments`; Karya validates that
contract at runtime and does not auto-generate compensation jobs from step
metadata alone. When an operator requests rollback for a failed workflow,
Karya creates a separate rollback batch and enqueues compensation jobs for
succeeded compensable steps in reverse definition order. Queued compensation
work is dependency-gated so rollback runs one compensation job at a time. If
every succeeded step is uncompensated, rollback records the operator boundary
without adding jobs.

### Batch Identity And Aggregate State

Workflow batches give related runtime jobs one stable identity. Batch creation
is atomic with bulk enqueue: either every member job and the batch membership
are stored, or none of them are. Membership is immutable for a created batch,
so later inspection can derive aggregate state from the current member jobs
without guessing which jobs belong together.

Batch aggregate state is derived from member job lifecycle state:

- `failed` when any member is failed or dead-lettered
- `running` while any member remains queued, reserved, running, retry-pending,
  or otherwise nonterminal
- `succeeded` when every member succeeded
- `cancelled` when every member was cancelled
- `completed` for terminal mixed success and cancellation outcomes

## Related Concepts

- [Job Model](/runtime/job-model/): workflows build on the core job runtime
- [Replay](/workflows/replay/): recovery depends on the same execution story
- [Signals](/workflows/signals/): live interaction matters once the workflow is running
- [Versioning](/workflows/versioning/): durable workflows eventually need evolution rules
