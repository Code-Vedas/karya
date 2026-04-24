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
