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

This is not event-history replay. Operators must name the target steps
explicitly; Karya does not infer targets from workflow state, create a new
workflow run, append batch membership, or reconstruct a workflow from a
timeline.

## Related Concepts

- [Signals](/workflows/signals/): interactive workflows need recovery and live control
- [Child Workflows](/workflows/child-workflows/): replay often involves parent-child
  relationships
- [Activity And Audit](/operator/activity-audit/): replay needs audit-safe
  operator history
