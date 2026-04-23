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
- explicit escalation from bounded retry into dead-letter isolation or other
  governed recovery paths when policy says work is no longer safe to continue

## Operator Expectations

Operators need to distinguish:

- failures that remain retry-eligible when policy allows
- failures that should wait in `retry_pending` until the next retry window
- failures that should stop normal retry and move into dead-letter isolation
  or other governed recovery flows
- failed attempts that transition into `retry_pending`
- escalation decisions that are driven by explicit policy rather than implicit
  worker behavior

## Common Scenarios

### Investigating A Retry Loop

Retry behavior should be understandable from an operator point of view:

```text
job: billing-123
attempt: 3
status: retry_pending
next_retry_at: 2026-03-26T14:05:00Z
reason: upstream timeout
recovery_boundary: bounded-retry
```

Retry state needs to be visible, explainable, and bounded.

- `failed` records the current attempt outcome
- `retry_pending` means the same job instance is still under retry policy
- `next_retry_at` marks the next planned re-entry into queued execution
- dead-letter isolation starts only after bounded retry stops being the right
  path for that job
- retry-policy escalation writes `dead_letter` with an operator-visible reason.
  Expired execution failures remain `failed` instead of escalating

## Related Concepts

- [Dead Letters](/reliability/dead-letters/): follow the path when bounded
  retry is no longer safe
- [Controls](/runtime/controls/): retry, isolation, and intervention follow
  the same operator workflows
- [Workflow Replay](/workflows/replay/): replay belongs to governed recovery,
  not ordinary retry
- [Troubleshooting](/troubleshooting/): use retry state during incident
  triage
