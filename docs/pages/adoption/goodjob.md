---
title: GoodJob
parent: Adoption
nav_order: 2
---

# GoodJob

GoodJob aligns naturally with Karya’s Postgres-first backend posture.

## Guidance

- start from the SQL-backed runtime model
- plan recurring work around the Kaal-backed scheduling story
- adopt workflows intentionally rather than assuming they are identical to
  background-job semantics

## Common Scenarios

### Staying SQL-First While Expanding Scope

GoodJob adoption often starts from the SQL-backed posture:

```text
current_system: goodjob
current_backend: postgres
target_backend: postgres
migration_focus: workflows, schedules, operator visibility
```

The real shift is not only backend continuity, but moving from job-only
thinking into Karya’s workflow and operator surfaces.

## Related Concepts

- [Backends](../backends.md): Postgres remains the default production path here
- [Workflow Basics](../workflows/basics.md): this is usually the biggest product
  expansion
- [Cutover And Rollback](cutover-rollback.md): backend continuity does not
  remove rollout planning
