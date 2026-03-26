---
title: Dead Letters
parent: Reliability
nav_order: 3
permalink: /reliability/dead-letters/
---

# Dead Letters

Karya isolates unrecoverable or unsafe work through explicit dead-letter and
poison-job handling flows.

## Covered Behavior

- dead-letter state transitions
- poison-job isolation
- replay, discard, and controlled retry paths
- operator investigation and audit-oriented recovery workflows

## Operator Expectations

Dead-letter handling should prevent endless retry loops while still preserving
clear recovery options and historical context.

## Common Scenarios

### Recovering Unrecoverable Work

Dead-letter state should make recovery intent obvious:

```text
job: email-991
status: dead-letter
reason: poison-job-detected
available_actions: replay, discard, inspect
```

Unrecoverable work is isolated, and the recovery options stay explicit.

## Related Concepts

- [Retries](retries.md): dead-letter state starts where bounded retries end
- [Activity And Audit](../operator/activity-audit.md): recovery actions need
  clear history
- [Troubleshooting](../troubleshooting.md): use dead-letter state during
  incident response
