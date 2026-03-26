---
title: Uniqueness
parent: Reliability
nav_order: 2
---

# Uniqueness

Karya documents uniqueness and deduplication as visible platform behavior rather
than hidden queue implementation logic.

## Covered Behavior

- idempotency expectations
- unique job semantics
- deduplication visibility for operators
- interactions with replay, bulk operations, and workflow-triggered execution

## What Good Uniqueness Looks Like

Teams need to see when work is suppressed, merged, or intentionally rejected by
uniqueness rules.

## Common Scenarios

### Preventing Duplicate Work

Uniqueness should be visible when duplicate work is submitted:

```text
enqueue job billing-sync account=42
result: duplicate-suppressed
existing_job_id: billing-sync-42
```

What matters is visibility into why new work was not accepted as a fresh
execution.

## Related Concepts

- [Job Model](../runtime/job-model.md): uniqueness is part of the job lifecycle
- [Dead Letters](dead-letters.md): separate duplicate suppression from failure
  isolation
- [Workflow Basics](../workflows/basics.md): consider uniqueness at the workflow
  entrypoint too
