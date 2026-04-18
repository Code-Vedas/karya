---
title: Dead Letters
parent: Reliability
nav_order: 3
permalink: /reliability/dead-letters/
---

# Dead Letters

Karya reserves dead-letter handling for reliability layers that extend the base
runtime lifecycle with explicit isolation and governed recovery flows.

## Covered Behavior

- dead-letter isolation after bounded retry or policy-based isolation in an
  extension layer
- operator-visible reasons why work left the normal retry path
- governed replay, discard, and controlled retry paths
- operator investigation and audit-oriented recovery workflows

## Operator Expectations

Dead-letter handling should prevent endless retry loops while still preserving
clear recovery options and historical context.

Dead-letter handling begins after work leaves the ordinary retry path. The
non-terminal execution and retry states include `queued`, `reserved`,
`running`, `failed`, and `retry_pending`; dead-letter handling covers the
isolated path that follows. The base runtime provides the extension boundary.
Adapters, queue stores, or higher-level operator workflows provide the
dead-letter policy and recovery actions built on top of it.

## Common Scenarios

### Recovering Unrecoverable Work

Dead-letter state should make recovery intent obvious:

```text
# persisted job attributes
job: email-991
state: dead_letter

# operator/UI metadata
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
