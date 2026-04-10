---
title: Retries
parent: Reliability
nav_order: 1
permalink: /reliability/retries/
---

# Retries

Retries are part of Karya’s runtime behavior, not an afterthought bolted onto
individual jobs.

## Covered Behavior

- retry and backoff policies
- operator-visible retry state and recovery boundaries

## Implemented In Core Runtime

- deterministic exponential backoff with optional max-delay cap
- worker-default retry policy with optional per-job override
- `retry_pending` as explicit waiting state between failed attempt and requeue
- lazy due-retry promotion during queue-store maintenance and reservation

## Deferred Follow-on Work

- jitter strategies and retry spread control
- escalation rules and dead-letter integration
- failure classification and richer operator recovery semantics
- named reusable retry policies

## Operator Expectations

Operators need to distinguish:

- normal retryable failures
- failed attempts that transition into `retry_pending`
- escalated failure states
- conditions that should move work into dead-letter or governed recovery flows

## Common Scenarios

### Investigating A Retry Loop

Retry behavior should be understandable from an operator point of view:

```text
job: billing-123
attempt: 3
status: retry_pending
next_retry_at: 2026-03-26T14:05:00Z
reason: upstream timeout
```

Retry state needs to be visible, explainable, and bounded.

In the current core runtime, `next_retry_at` is the scheduling boundary that
controls when a `retry_pending` job can return to `queued`. Due retries are
promoted lazily when the queue store performs maintenance work such as
reservation scans.

## Related Concepts

- [Dead Letters](/reliability/dead-letters/): follow the path when retries stop being safe
- [Controls](/runtime/controls/): replay, retry, and intervention share one
  control model
- [Workflow Replay](/workflows/replay/): replay builds on the same recovery
  expectations
- [Troubleshooting](/troubleshooting/): use retry state during incident
  triage
