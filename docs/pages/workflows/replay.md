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

- replay and failure-handling controls
- operator-driven recovery
- event-history and timeline inspection
- compatibility with compensation and audit-oriented workflows

## Common Scenarios

### Recovering A Failed Workflow

Replay should read as a controlled recovery action:

```text
workflow: invoice-closeout-204
status: failed
available_actions: inspect, replay, compensate
selected_action: replay
reason: downstream gateway recovered
```

Replay is a deliberate recovery action, backed by execution history and visible
to operators.

## Related Concepts

- [Signals](/workflows/signals/): interactive workflows need recovery and live control
- [Child Workflows](/workflows/child-workflows/): replay often involves parent-child
  relationships
- [Activity And Audit](/operator/activity-audit/): replay needs audit-safe
  operator history
