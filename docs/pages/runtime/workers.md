---
title: Workers
parent: Runtime
nav_order: 2
permalink: /runtime/workers/
---

# Workers

Workers are responsible for reserving work, executing jobs, and participating in
coordinated runtime lifecycle behavior.

## Worker Responsibilities

- subscribe to the correct queues
- reserve jobs without violating routing and fairness rules
- execute work while respecting timeouts, expirations, and cancellation
- participate in graceful shutdown and drain behavior

## Supervision And Lifecycle

Karya documents worker behavior around:

- bootstrap and execution flow
- drain-safe shutdown
- pause and resume interactions with queue state
- runtime supervision hooks used by operators and automation

## Operator View

Worker state is surfaced consistently through:

- dashboard worker views
- operator APIs
- CLI-oriented control and inspection commands

## Common Scenarios

### Executing Reserved Work

Workers are the runtime-side executors for queued work:

```ruby
class BillingWorker
  def run
    loop do
      # Reserve work, execute it, and honor shutdown/drain signals.
    end
  end
end
```

Workers reserve work, execute it, and respond cleanly to
shutdown and control signals.

## Related Concepts

- [Job Model](/runtime/job-model/): worker behavior starts from the job lifecycle
- [Controls](/runtime/controls/): operators supervise workers through shared surfaces
- [Backpressure](/reliability/backpressure/): rate limits and queue pressure
  shape worker behavior
- [Dashboard](/operator/dashboard/): worker state must stay visible to
  operators
