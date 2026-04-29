---
title: Versioning
parent: Workflows
nav_order: 5
permalink: /workflows/versioning/
---

# Workflow Versioning

Long-lived workflows require explicit evolution rules. Workflow versioning lets
teams evolve orchestration safely over time.

## Covered Behavior

- version boundaries
- safe evolution semantics
- upgrade and migration expectations for persisted workflow state
- operator guidance during cutovers and compatibility windows

## Workflow Identity

Workflow versioning is explicit runtime identity rather than a naming
convention hidden in application code.

- `workflow_family` is the stable product-facing workflow line, such as
  `invoice-closeout`
- `workflow_version` is the exact definition version, such as `v1` or `v2`
- `workflow_id` identifies the concrete registered definition that a run
  actually uses

New submissions resolve through the workflow family. Running and persisted
workflow batches stay bound to the exact workflow version selected at
submission time.

## Safe Evolution Rules

Versioning keeps the coexistence boundary explicit:

- new submissions can resolve to a newer default version within the same
  workflow family
- existing workflow batches stay on their captured version
- replay, rollback, pause or resume, approvals, signals, and child-workflow
  synchronization continue against that bound version
- incompatible workflow changes require a new version instead of mutating the
  meaning of an existing one

This model keeps long-running execution understandable during cutovers and
avoids silent rebinding when definitions change.

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

In that window:

- new workflow submissions can target `v2`
- in-flight `v1` batches continue to inspect, recover, and complete as `v1`
- operators can reason about recovery without guessing which definition a batch
  now means

### Safe Change Types

Versioning supports additive and intentional change, not silent semantic drift.

Typical safe patterns include:

- adding a new version for incompatible step ordering or dependency changes
- introducing new checkpoints or child workflows behind a new version boundary
- keeping older versions available until active batches have drained

Typical unsafe patterns include:

- changing the meaning of an in-flight step inside the same bound version
- rebinding persisted batches to a newer definition without an explicit version
  transition
- assuming replay reconstructs a workflow from a new definition or event
  history

### Persisted Workflow Behavior

Persisted workflow state stays version-bound. Coexistence windows are the
standard cutover shape for live workflow batches.

- version selection happens at submission time
- persisted workflow snapshots keep both workflow family and workflow version
- older and newer versions can coexist during rollout
- migration or rebind controls are separate product surfaces, not an implicit
  side effect of registering a new definition

## Related Concepts

- [Rollout](/governance/rollout/): workflow evolution and release controls
  must agree
- [Replay](/workflows/replay/): recovery behavior changes when multiple versions coexist
- [Cutover And Rollback](/adoption/cutover-rollback/): versioning affects
  rollout planning
