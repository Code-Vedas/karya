---
title: Backpressure
parent: Reliability
nav_order: 4
permalink: /reliability/backpressure/
---

# Backpressure

Backpressure, fairness, and starvation prevention are documented as intentional
behavior under constrained capacity.

## Covered Behavior

- fairness between queues and workers
- starvation prevention
- concurrency groups and scoped rate limits
- overload handling and automated recovery hooks
- queue-local priority ordering inside otherwise eligible work

## Operator Expectations

Operators need to understand whether delay comes from queue pressure,
rate limits, concurrency caps, paused state, or backend-specific constraints.

In `core/karya`, backpressure policy is modeled through
`Karya::Backpressure::PolicySet`. Concurrency policies cap active `reserved` and
`running` jobs sharing one `concurrency_key`. Rate-limit policies use fixed
windows keyed by `rate_limit_key` and consume capacity when reservation
succeeds.

## Common Scenarios

### Explaining A Growing Queue

Backpressure should read as an operational state, not an unexplained slowdown:

```text
queue: billing
status: throttled
reason: concurrency-group-limit
running_jobs: 25
waiting_jobs: 140
```

What matters is that delayed work is explainable. Operators need to
tell whether pressure comes from limits, congestion, or a paused execution
path.

## Related Concepts

- [Workers](/runtime/workers/): worker throughput and drain behavior affect
  pressure directly
- [Search And Drilldowns](/operator/search-drilldowns/): operators need to
  drill into the queues under pressure
- [Backends](/backends/): backend characteristics shape how pressure is felt
