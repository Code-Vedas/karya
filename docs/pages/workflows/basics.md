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

```text
workflow: invoice-closeout
steps:
  - calculate_totals
  - capture_payment
  - emit_receipt
on_failure:
  - compensate prior completed steps in reverse order
```

This is the core idea: Karya treats related work as one inspectable workflow,
not a pile of unrelated background jobs.

## Related Concepts

- [Job Model](../runtime/job-model.md): workflows build on the core job runtime
- [Replay](replay.md): recovery depends on the same execution story
- [Signals](signals.md): live interaction matters once the workflow is running
- [Versioning](versioning.md): durable workflows eventually need evolution rules
