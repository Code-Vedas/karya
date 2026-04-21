---
title: Uniqueness
parent: Reliability
nav_order: 2
permalink: /reliability/uniqueness/
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

Karya's core v1 uniqueness behavior is reject-only. Duplicate job identities,
idempotency keys, or active uniqueness windows reject fresh enqueue attempts
instead of silently merging, replacing, or acknowledging them as success. Later
bulk and operator recovery surfaces may add mutation workflows, but those are
separate controls.

## Common Scenarios

### Preventing Duplicate Work

Uniqueness should be visible before or when duplicate work is submitted:

```text
enqueue job billing-sync account=42
result: duplicate_uniqueness_key
action: reject
conflicting_job_id: billing-sync-42
```

What matters is visibility into why new work was not accepted as a fresh
execution.

### Inspecting A Decision

Operators and tooling can preflight a candidate job with a uniqueness decision.
The decision reports whether Karya would accept or reject the job, which key
caused the rejection, and the conflicting job id when one exists.

```text
uniqueness_decision job=billing-sync-43
action: reject
result: duplicate_idempotency_key
key_type: idempotency_key
conflicting_job_id: billing-sync-42
```

Decision inspection is read-only. It does not enqueue the candidate job, record
the rejected attempt, recover expired leases, or promote retry-pending work.

### Inspecting Current Blockers

A uniqueness snapshot shows the keys currently influencing enqueue decisions:

- idempotency keys remain blockers while the original job remains stored
- uniqueness keys show effective blockers and the incoming scopes they block
- due retry-pending work and expired in-flight leases are evaluated as their
  effective uniqueness state for inspection without mutating runtime state

## Related Concepts

- [Job Model](/runtime/job-model/): uniqueness is part of the job lifecycle
- [Dead Letters](/reliability/dead-letters/): separate duplicate suppression from failure
  isolation
- [Workflow Basics](/workflows/basics/): consider uniqueness at the workflow
  entrypoint too
