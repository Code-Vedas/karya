---
title: Backpressure
parent: Reliability
nav_order: 4
permalink: /reliability/backpressure/
---

# Backpressure

Backpressure, fairness, and starvation prevention are intentional runtime
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

Circuit breaking is adjacent to backpressure, but it is not the same control.
Backpressure explains constrained capacity or policy windows. Circuit breakers
explain intentionally suppressed execution after repeated unhealthy outcomes on
one queue or handler path.

Backpressure is not only about raw queue depth. It also depends on whether
workers are subscribed to the right queues, whether handlers match the routed
work, and whether the selected work is allowed through the current policy
window.

Concurrency policies cap active work sharing one `concurrency_key`.
Rate-limit policies constrain reservation over a scoped rolling window keyed by
`rate_limit_key`. Priority influences selection among otherwise eligible work
inside a queue, but it does not replace explicit routing or eliminate pressure.

Fairness policy controls how a worker scans multiple subscribed queues:

- `round_robin` is the default and starts each multi-queue reservation scan
  after the queue that most recently produced work, preventing a permanently
  busy first queue from starving later eligible queues
- `strict_order` preserves declared queue order as fixed preference for callers
  that intentionally want earlier queues to drain first

Fairness applies between queues, not within one queue. Inside a queue,
higher-priority jobs win over lower-priority jobs, and jobs with equal priority
keep FIFO order. Jobs blocked by pause, handler mismatch, concurrency,
rate-limit windows, circuit breakers, or dead-letter isolation stay queued; the
store skips them and continues looking for later eligible work.

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
- [Circuit Breakers](/reliability/circuit-breakers/): unhealthy execution
  paths should not be mistaken for ordinary capacity pressure
- [Search And Drilldowns](/operator/search-drilldowns/): operators need to
  drill into the queues under pressure
- [Backends](/backends/): backend characteristics shape how pressure is felt
