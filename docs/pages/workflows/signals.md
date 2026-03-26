---
title: Signals
parent: Workflows
nav_order: 3
---

# Workflow Signals

Karya supports live interaction with running workflows through signals, queries,
and external events.

## Covered Behavior

- signal delivery into running workflows
- query access to workflow state
- external event handling
- pause, resume, and approval checkpoints

## Why It Matters

These controls let operators and applications interact with live workflow state
without bypassing workflow rules.

## Common Scenarios

### Interacting With A Running Workflow

Signals and queries should expose live interaction without mutating workflow
state out of band:

```text
workflow: invoice-closeout-204
signal: manager-approved
query: current-step
response: capture_payment
```

Running workflows stay interactive and inspectable through supported surfaces.

## Related Concepts

- [Replay](replay.md): live interaction and recovery belong to the same
  operator story
- [Child Workflows](child-workflows.md): signals often affect workflow
  hierarchies
- [Dashboard](../operator/dashboard.md): operators need these controls in the UI
