---
title: Versioning
parent: Workflows
nav_order: 5
---

# Workflow Versioning

Long-lived workflows require explicit evolution rules. Karya documents
versioning so teams can change orchestration safely over time.

## Covered Behavior

- version boundaries
- safe evolution semantics
- upgrade and migration expectations for persisted workflow state
- operator guidance during cutovers and compatibility windows

## Common Scenarios

### Rolling Out A New Workflow Version

Versioning should make long-lived workflow evolution understandable:

```text
workflow_family: invoice-closeout
running_versions:
  - v1
new_submissions:
  - v2
compatibility_window: active
```

Version boundaries and operator expectations need to stay explicit, especially
when long-lived executions cross rollout windows.

## Related Concepts

- [Rollout](../governance/rollout.md): workflow evolution and release controls
  must agree
- [Replay](replay.md): recovery behavior changes when multiple versions coexist
- [Cutover And Rollback](../adoption/cutover-rollback.md): versioning affects
  rollout planning
