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

## Related Concepts

- [Job Model](/runtime/job-model/): workflows build on the core job runtime
- [Replay](/workflows/replay/): recovery depends on the same execution story
- [Signals](/workflows/signals/): live interaction matters once the workflow is running
- [Versioning](/workflows/versioning/): durable workflows eventually need evolution rules
