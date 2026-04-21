---
title: Circuit Breakers
parent: Reliability
nav_order: 2
permalink: /reliability/circuit-breakers/
---

# Circuit Breakers

Karya uses circuit breakers to stop unhealthy execution paths from creating
cascading failure loops while keeping the blocked work visible and explainable.

## Covered Behavior

- queue- and handler-scoped breaker policies
- breaker transitions between `closed`, `open`, and `half_open`
- cooldown-based probe recovery instead of immediate retry churn
- inspection surfaces that show blocked work without rewriting job lifecycle

## Breaker Behavior

- breaker policies are scoped to `queue:*` or `handler:*`
- counted failures are execution `:error` and `:timeout`
- `:expired` is visible failure data but does not trip a breaker
- when the failure threshold is reached inside the configured window, the
  breaker opens for that scope
- open breakers leave matching jobs in `queued`; they do not force `failed`,
  `retry_pending`, or dead-letter state by themselves
- after cooldown, the breaker moves to `half_open` and allows a bounded probe
  set
- a successful probe closes the breaker and clears breaker-local failure
  history
- a failed probe re-opens the breaker immediately and starts a new cooldown

## Operator Expectations

Circuit breakers and backpressure are related but different:

- backpressure explains capacity, fairness, concurrency, and rate-limit blocks
- circuit breakers explain health-based execution suppression after repeated
  failures

Operators should be able to tell whether queued work is delayed because the
runtime is overloaded, the route is mismatched, or the execution path has been
opened by a breaker.

## Common Scenarios

### Investigating A Breaker-Open Queue

Inspection vocabulary should make the block legible:

```text
scope: queue:billing
state: open
failure_count: 3
failure_threshold: 3
cooldown_until: 2026-04-08T12:00:14Z
blocked_count: 42
```

The queue still contains work, but execution is intentionally paused for that
scope until cooldown and half-open probing say it is safe to resume.

## Related Concepts

- [Backpressure](/reliability/backpressure/): pressure explains capacity
  blocks, not unhealthy execution paths
- [Retries](/reliability/retries/): retries remain lifecycle state; breakers
  suppress new execution without inventing a new job state
- [Controls](/runtime/controls/): operator inspection should expose the same
  breaker vocabulary across surfaces
- [Troubleshooting](/troubleshooting/): use breaker state to separate unhealthy
  paths from ordinary backlog pressure
