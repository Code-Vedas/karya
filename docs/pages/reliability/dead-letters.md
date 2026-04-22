---
title: Dead Letters
parent: Reliability
nav_order: 3
permalink: /reliability/dead-letters/
---

# Dead Letters

Karya isolates unrecoverable or unsafe work through explicit dead-letter
handling and governed recovery flows.

## Covered Behavior

- dead-letter isolation after bounded retry or policy-based isolation
- operator-visible reasons why work left the normal retry path
- governed replay, discard, and controlled retry paths
- operator investigation and audit-oriented recovery workflows

## Operator Expectations

Dead-letter handling should prevent endless retry loops while still preserving
clear recovery options and historical context.

Dead-letter handling begins after work leaves the ordinary retry path. The
non-terminal execution and retry states include `queued`, `reserved`,
`running`, `failed`, `retry_pending`, and `dead_letter`. A `dead_letter` job is
stored and inspectable, but it is not eligible for reservation or automatic
retry promotion.

Core recovery actions are bounded by explicit job ids:

- replay moves `dead_letter` work directly back to `queued`
- controlled retry moves `dead_letter` work to `retry_pending` for a supplied
  `next_retry_at`
- discard moves `dead_letter` work to `cancelled`

Automatic retry-policy escalation also moves work into `dead_letter` when a
classification is configured for escalation or retry attempts are exhausted.
Expired work remains `failed` with the `expired` classification.

## Common Scenarios

### Recovering Unrecoverable Work

Dead-letter state should make recovery intent obvious:

```text
job: email-991
state: dead_letter

reason: retry-policy-exhausted
last_state: retry_pending
recovery_boundary: governed
available_actions: replay, discard, inspect
```

Unrecoverable work is isolated, and the recovery options stay explicit. Retry
is no longer the default behavior. Investigation and governed action take over
from routine runtime recovery.

In-memory inspection exposes dead-letter snapshots with job identity, routing,
attempt count, failure classification, isolation reason, source state, and
available recovery actions.

## Related Concepts

- [Retries](/reliability/retries/): dead-letter isolation starts where bounded
  retry ends
- [Job Model](/runtime/job-model/): dead-letter handling follows the canonical
  lifecycle without replacing it
- [Activity And Audit](/operator/activity-audit/): recovery actions need
  clear history
- [Troubleshooting](/troubleshooting/): use dead-letter state during
  incident response
