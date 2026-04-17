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

- dead-letter isolation after bounded retry or policy-based escalation
- operator-visible reasons why work left the normal retry path
- governed replay, discard, and controlled retry paths
- operator investigation and audit-oriented recovery workflows

## Operator Expectations

Dead-letter handling should prevent endless retry loops while still preserving
clear recovery options and historical context.

Dead-letter handling begins after work leaves the ordinary retry path. The
canonical lifecycle covers `queued`, `reserved`, `running`, `failed`, and
`retry_pending`; dead-letter handling covers the isolated path that follows.

## Common Scenarios

### Recovering Unrecoverable Work

Dead-letter state should make recovery intent obvious:

```text
job: email-991
status: dead-letter
reason: retry-policy-exhausted
last_state: retry_pending
recovery_boundary: governed
available_actions: replay, discard, inspect
```

Unrecoverable work is isolated, and the recovery options stay explicit. Retry
is no longer the default behavior. Investigation and governed action take over
from routine runtime recovery.

## Related Concepts

- [Retries](/reliability/retries/): dead-letter isolation starts where bounded
  retry ends
- [Job Model](/runtime/job-model/): dead-letter handling follows the canonical
  lifecycle without replacing it
- [Activity And Audit](/operator/activity-audit/): recovery actions need
  clear history
- [Troubleshooting](/troubleshooting/): use dead-letter state during
  incident response
