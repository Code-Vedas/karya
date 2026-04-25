---
title: Replay
parent: Workflows
nav_order: 2
permalink: /workflows/replay/
---

# Workflow Replay

Replay is a first-class recovery and investigation feature for workflow-based
execution.

## Covered Behavior

- explicit step-targeted retry, dead-letter, replay, retry-dead-letter, and
  discard controls
- operator-driven recovery against the current primary workflow batch
- current-state recovery that preserves immutable workflow batch membership
- compatibility with compensation and audit-oriented workflows without
  automatic rollback

## Common Scenarios

### Recovering A Failed Workflow

Replay should read as a controlled recovery action over explicit workflow step
ids:

```text
workflow_batch_id: invoice-closeout-204
step_ids: authorize, capture
selected_action: replay_workflow_steps
reason: downstream gateway recovered
```

Workflow step controls resolve step ids to the current primary step job ids,
then apply the same lifecycle rules as job-id controls. Retried and replayed
steps stay in the original workflow batch; prerequisite gating continues to
decide when dependent queued steps can reserve.

`replay_workflow_steps`, `retry_dead_letter_workflow_steps`, and
`discard_workflow_steps` only act when the targeted primary step job is
currently `:dead_letter`. If the primary job is failed, queued, running, or in
any other ineligible state, Karya leaves it unchanged and reports the targeted
step as skipped.

This is not event-history replay. Operators must name the target steps
explicitly; Karya does not infer targets from workflow state, create a new
workflow run, append batch membership, or reconstruct a workflow from a
timeline.

### Step Retry

Use retry when a failed or retry-pending primary step job should return to
normal queued execution:

```text
workflow_batch_id: invoice-closeout-204
selected_action: retry_workflow_steps
step_ids: capture_payment
expected_result: capture_payment queues again; emit_receipt stays blocked until capture_payment succeeds
```

### Dead-Letter Replay

Use replay when a primary workflow step has been isolated in `dead_letter` and
the operator wants it to re-enter queued execution:

```text
workflow_batch_id: invoice-closeout-204
selected_action: replay_workflow_steps
step_ids: capture_payment
expected_result: original workflow batch membership is unchanged
```

Use controlled dead-letter retry when the step should wait for a planned retry
window:

```text
workflow_batch_id: invoice-closeout-204
selected_action: retry_dead_letter_workflow_steps
step_ids: capture_payment
next_retry_at: 2026-04-24T15:30:00Z
expected_result: capture_payment enters retry_pending
```

Use discard when the operator decides a dead-lettered step should be cancelled:

```text
workflow_batch_id: invoice-closeout-204
selected_action: discard_workflow_steps
step_ids: capture_payment
expected_result: capture_payment becomes cancelled; dependents do not unblock
```

### Rollback Boundary

Rollback is separate from replay. It is an explicit operator action for
workflow batches whose workflow snapshot is already `:failed` and no longer has
active or runnable work remaining:

```text
workflow_batch_id: invoice-closeout-204
selected_action: rollback_workflow
reason: payment provider settlement failed
expected_result: compensation jobs are enqueued in a separate rollback batch
```

If the workflow still has reserved, running, retry-pending, or dependency-ready
queued work, `rollback_workflow` rejects the request as an invalid execution
instead of starting compensation early.

Rollback compensates succeeded compensable primary steps in reverse workflow
definition order. If no succeeded step has compensation, Karya records the
rollback request boundary without creating a physical rollback batch.

## Related Concepts

- [Signals](/workflows/signals/): interactive workflows need recovery and live control
- [Child Workflows](/workflows/child-workflows/): replay often involves parent-child
  relationships
- [Activity And Audit](/operator/activity-audit/): replay needs audit-safe
  operator history
