---
title: Backpressure
parent: Reliability
nav_order: 4
---

# Backpressure

Backpressure, fairness, and starvation prevention are documented as intentional
behavior under constrained capacity.

## Covered Behavior

- fairness between queues and workers
- starvation prevention
- concurrency groups and scoped rate limits
- overload handling and automated recovery hooks

## Operator Expectations

Operators need to understand whether delay comes from queue pressure,
rate limits, concurrency caps, paused state, or backend-specific constraints.

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

- [Workers](../runtime/workers.md): worker throughput and drain behavior affect
  pressure directly
- [Search And Drilldowns](../operator/search-drilldowns.md): operators need to
  drill into the queues under pressure
- [Backends](../backends.md): backend characteristics shape how pressure is felt
