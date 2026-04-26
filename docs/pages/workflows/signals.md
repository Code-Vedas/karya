---
title: Signals
parent: Workflows
nav_order: 3
permalink: /workflows/signals/
---

# Workflow Signals

Karya supports live interaction with running workflows through signals, queries,
external events, and operator checkpoints.

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

- [Replay](/workflows/replay/): live interaction and recovery belong to the same
  operator story
- [Child Workflows](/workflows/child-workflows/): signals often affect workflow
  hierarchies
- [Dashboard](/operator/dashboard/): operators need these controls in the UI
