---
title: Child Workflows
parent: Workflows
nav_order: 4
---

# Child Workflows

Child workflows and subflow orchestration are documented as explicit workflow
primitives.

## Covered Behavior

- parent-child lifecycle relationships
- success, failure, cancellation, and recovery behavior
- operator visibility across related executions

## Operational Expectations

Operators need to inspect workflow hierarchies clearly rather than treating
subflows as opaque implementation detail.

## Common Scenarios

### Inspecting A Workflow Hierarchy

Child workflows should surface parent-child relationships directly:

```text
parent_workflow: order-fulfillment-88
child_workflows:
  - payment-authorization-88
  - shipment-booking-88
status: waiting-on-children
```

Subflows remain visible execution units with explicit relationships.

## Related Concepts

- [Workflow Basics](basics.md): child workflows extend the orchestration model
- [Replay](replay.md): parent-child recovery should stay understandable
- [Search And Drilldowns](../operator/search-drilldowns.md): operators need to
  move between parent and child detail views
