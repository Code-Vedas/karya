---
title: Retries
parent: Reliability
nav_order: 1
permalink: /reliability/retries/
---

# Retries

Retries are part of Karya’s product reliability model, not an afterthought
bolted onto individual jobs.

## Covered Behavior

- retry and backoff policies
- operator-visible retry state
- the boundary between retry, isolation, and governed recovery

## Retry Behavior

- deterministic exponential backoff with optional max-delay cap
- worker-default retry policy with optional per-job override
- `retry_pending` as explicit waiting state between failed attempt and requeue
- operator-visible failure classification and retry timing
- a handoff point where extensions or higher-level operator workflows may
  isolate work after bounded retry stops being the right path

## Operator Expectations

Operators need to distinguish:

- failures that remain retry-eligible when policy allows
- failures that should wait in `retry_pending` until the next retry window
- failures that stop normal retry and remain `failed` until another lifecycle
  extension or higher-level recovery workflow takes over
- failed attempts that transition into `retry_pending`
- the difference between core retry behavior and later isolation or recovery
  layers

## Common Scenarios

### Investigating A Retry Loop

Retry behavior should be understandable from an operator point of view:

```text
# persisted job attributes
job: billing-123
attempt: 3
status: retry_pending
next_retry_at: 2026-03-26T14:05:00Z
failure_classification: timeout
```

Retry state needs to be visible, explainable, and bounded.

- `failed` records the current attempt outcome
- `retry_pending` means the same job instance is still under retry policy
- `next_retry_at` marks the next planned re-entry into queued execution
- when retries are exhausted, the core runtime returns the job to `failed`
- dead-letter isolation requires additional lifecycle or queue-store behavior
  beyond the base retry model

## Related Concepts

- [Dead Letters](/reliability/dead-letters/): follow the path when bounded
  retry is no longer safe
- [Controls](/runtime/controls/): retry, isolation, and intervention follow
  the same operator workflows
- [Workflow Replay](/workflows/replay/): replay sits in governed recovery,
  not ordinary retry
- [Troubleshooting](/troubleshooting/): use retry state during incident
  triage
