---
title: Activity And Audit
parent: Operator
nav_order: 5
permalink: /operator/activity-audit/
---

# Activity And Audit

Operators need to understand what changed, when it changed, and who initiated
the change.

## Covered Behavior

- live activity feeds
- audit timelines
- bulk actions with governed recovery boundaries
- investigation flows for workflow and runtime history

## Common Scenarios

### Reviewing Operator History

Activity and audit surfaces should make operator history readable:

```text
timestamp: 2026-03-26T14:02:00Z
actor: operator:alice
action: replay workflow invoice-closeout-204
result: accepted
```

Operator-visible history should support investigation, recovery, and
auditability.

## Related Concepts

- [Replay](/workflows/replay/): high-impact workflow actions belong in the
  audit trail
- [Policies](/governance/policies/): governed actions and policy decisions
  need history too
- [Dashboard](/operator/dashboard/): actions taken in the UI should remain visible later
