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
- workflow-history inspection for one workflow batch at a time
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

Workflow history is an explicit execution journal rather than an inferred view
of current workflow state. Timeline entries can include workflow registration,
step lifecycle transitions, delivered signals and events, pause and resume
actions, approval decisions, replay and rollback controls, and child-workflow
boundaries.

## Related Concepts

- [Replay](/workflows/replay/): high-impact workflow actions belong in the
  audit trail
- [Policies](/governance/policies/): governed actions and policy decisions
  need history too
- [Dashboard](/operator/dashboard/): actions taken in the UI should remain visible later
