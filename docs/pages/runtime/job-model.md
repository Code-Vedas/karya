---
title: Job Model
parent: Runtime
nav_order: 1
permalink: /runtime/job-model/
---

# Job Model

Jobs are the canonical executable unit in Karya. The job model anchors queueing,
worker execution, retry behavior, workflow composition, and operator
inspection.

## Core Expectations

- a job has an explicit lifecycle rather than an implicit fire-and-forget state
- queues determine where work is routed
- workers reserve jobs according to the runtime and reliability contracts
- operators can inspect job state through UI, API, and CLI surfaces

## Lifecycle Boundaries

The documented lifecycle includes:

- enqueue and reservation
- active execution
- completion or failure
- replay, retry, cancellation, or dead-letter transitions where applicable

## Why This Matters

Downstream features such as uniqueness, bulk operations, workflow steps,
approval checkpoints, and governed actions all rely on a stable job model.

## Common Scenarios

### Defining Application Work

Use a job as the smallest durable unit of application work:

```ruby
module BillingJob
  def self.perform(account_id:, amount_cents:)
    # Application work runs here.
  end
end
```

Application code defines executable work, and Karya owns the routing,
lifecycle, and operator-visible state around it.

## Related Concepts

- [Workers](/runtime/workers/): see how jobs are reserved and executed
- [Controls](/runtime/controls/): inspect and intervene in runtime state
- [Retries](/reliability/retries/): understand how failed jobs re-enter the
  runtime
- [Workflow Basics](/workflows/basics/): see when a single job becomes a
  workflow
