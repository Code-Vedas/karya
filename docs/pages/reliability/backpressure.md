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

- routing-aware fairness between queues and workers
- starvation prevention
- concurrency groups and scoped rate limits
- overload handling and recovery boundaries
- queue-local priority ordering inside otherwise eligible work

## Operator Expectations

Operators need to understand whether delay comes from queue pressure,
rate limits, concurrency caps, routing mismatches, or backend-specific
constraints.

Backpressure is not only about raw queue depth. It also depends on whether
workers are subscribed to the right queues, whether handlers match the routed
work, and whether the selected work is allowed through the current policy
window.

Concurrency policies cap active work sharing one `concurrency_key`.
Rate-limit policies constrain reservation over a scoped rolling window keyed by
`rate_limit_key`. Priority influences selection among otherwise eligible work
inside a queue, but it does not replace explicit routing or eliminate pressure.

## Common Scenarios

### Explaining A Growing Queue

Backpressure should read as an operational state, not an unexplained slowdown:

```text
queue: billing
status: throttled
reason: concurrency-group-limit
queues: [billing]
handlers: [billing_sync]
running_jobs: 25
waiting_jobs: 140
```

What matters is that delayed work is explainable. Operators need to
tell whether pressure comes from limits, congestion, or routing and
subscription shape.

## Related Concepts

- [Workers](/runtime/workers/): worker throughput and drain behavior affect
  pressure directly
- [Retries](/reliability/retries/): pressure and failure handling meet at the
  retry boundary
- [Search And Drilldowns](/operator/search-drilldowns/): operators need to
  drill into the queues under pressure
- [Backends](/backends/): backend characteristics shape how pressure is felt
