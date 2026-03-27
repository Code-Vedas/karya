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
- jitter and escalation rules
- timeout, expiration, and failure classification interactions
- operator-visible retry state and recovery boundaries

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

## Related Concepts

- [Dead Letters](/reliability/dead-letters/): follow the path when retries stop being safe
- [Controls](/runtime/controls/): replay, retry, and intervention share one
  control model
- [Workflow Replay](/workflows/replay/): replay builds on the same recovery
  expectations
- [Troubleshooting](/troubleshooting/): use retry state during incident
  triage
