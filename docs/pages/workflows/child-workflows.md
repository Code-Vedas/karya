---
title: Child Workflows
parent: Workflows
nav_order: 4
permalink: /workflows/child-workflows/
---

# Child Workflows

Child workflows and subflow orchestration are explicit relationships between
workflow batches. A parent step can declare that it is backed by a child
workflow, and the child run is enqueued as its own immutable workflow batch.

## Covered Behavior

- parent-child lifecycle relationships
- success, failure, cancellation, and recovery behavior
- operator visibility across related executions
- explicit sync boundaries instead of hidden background propagation

## Operational Expectations

Operators need to inspect workflow hierarchies clearly rather than treating
subflows as opaque implementation detail. Child workflow batches remain normal
workflow batches: they can be inspected, retried, replayed, rolled back, and
recovered by their own batch id.

Parent-child propagation is explicit. Karya does not automatically enqueue a
child workflow from worker execution, and it does not automatically cascade
rollback between parent and child workflows.

## Common Scenarios

### Declaring A Child Step

```ruby
parent = Karya::Workflow.define(:order_fulfillment) do
  step :validate_order, handler: :validate_order
  step :payment, handler: :payment_gate, depends_on: :validate_order, child_workflow: :payment_authorization
  step :ship_order, handler: :ship_order, depends_on: :payment
end
```

The `payment` step still binds to one concrete parent job. That job acts as the
parent-side gate for downstream dependencies, and it is not reservable until
the child workflow succeeds.

### Enqueuing The Child Workflow

```ruby
store.enqueue_child_workflow(
  parent_batch_id: :order_88,
  parent_step_id: :payment,
  definition: payment_authorization,
  jobs_by_step_id: payment_jobs,
  batch_id: :payment_authorization_88,
  now: Time.now
)
```

The child workflow batch is separate from the parent batch. Parent membership
does not grow when a child is enqueued.

### Inspecting A Workflow Hierarchy

Child workflows surface parent-child relationships directly:

```text
parent_workflow: order-fulfillment-88
child_workflows:
  - payment-authorization-88
  - shipment-booking-88
status: waiting-on-children
```

Subflows remain visible execution units with explicit relationships.

```ruby
snapshot = store.workflow_snapshot(batch_id: :order_88, now: Time.now)

snapshot.fetch_step(:payment).child_workflow.child_batch_id
#=> "payment_authorization_88"

store.workflow_snapshot(batch_id: :payment_authorization_88, now: Time.now).parent.parent_batch_id
#=> "order_88"
```

### Synchronizing Lifecycle State

When a child workflow succeeds, the parent gate step becomes reservable and the
worker completes that gate job normally. When a child workflow fails or is
cancelled, operators synchronize the relationship explicitly:

```ruby
store.sync_child_workflows(parent_batch_id: :order_88, now: Time.now)
```

Sync propagates terminal child failure or cancellation to the parent child-step
job. It does not roll back parent or child workflows automatically.

## Related Concepts

- [Workflow Basics](/workflows/basics/): child workflows extend the orchestration model
- [Replay](/workflows/replay/): parent-child recovery should stay understandable
- [Search And Drilldowns](/operator/search-drilldowns/): operators need to
  move between parent and child detail views
