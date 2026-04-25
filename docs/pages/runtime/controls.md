---
title: Controls
parent: Runtime
nav_order: 3
permalink: /runtime/controls/
---

# Controls

Karya documents runtime controls through aligned dashboard, operator API, and
CLI surfaces.

## Supported Control Types

- runtime inspection APIs for supervisor, child-process, and worker-thread state
- supervisor-level drain and force-stop controls for worker runtimes
- queue and worker lifecycle control
- bounded bulk enqueue, retry, and cancellation actions over explicit job ids
- queue pause and resume controls that block future reservation without
  mutating queued work
- retry, isolation, replay, and governed recovery actions across aligned
  operator surfaces
- breaker-open, half-open, and stuck-work inspection vocabulary for unhealthy
  execution paths
- operator-visible state used for safe intervention across `queued`,
  `reserved`, `running`, `failed`, `retry_pending`, `dead_letter`, and
  `cancelled`

## Surface Model

- dashboard: live investigation and operator action
- operator API: integration and automation
- CLI: local operations and scripted control

## Relationship To Other Sections

Runtime controls define the safe entrypoints. Reliability, workflow, and
governance features extend those same control boundaries rather than creating
separate operational models.

The control surface uses the same canonical lifecycle vocabulary defined in the
job model rather than redefining job state per interface.

## Common Scenarios

### Taking A Runtime Action

Illustrative vocabulary across UI, API, and CLI surfaces:

```text
dashboard action: retry failed job <job-id>
dashboard action: pause queue billing
dashboard action: inspect dead_letter job <job-id>
dashboard action: inspect circuit_breaker queue:billing
operator API action: replay isolated job <job-id>
CLI action: karya runtime inspect --state-file /tmp/karya-runtime-billing.json
```

Dashboard, operator API, and CLI workflows use the same runtime vocabulary for
inspection and intervention.

### Bulk Queue Actions

Core queue-store controls support bounded bulk actions before higher-level
operator search and governance layers choose targets:

- bulk enqueue is atomic; any invalid or duplicate item rejects the whole batch
  without partial writes
- bulk enqueue can attach a stable workflow batch id; batch membership is
  immutable, and aggregate batch state is inspected from current member jobs
- workflow enqueue stores all step jobs in one immutable batch and gates
  reservation of dependent steps until prerequisite jobs have succeeded
- workflow snapshots derive workflow state from stored workflow metadata and
  current member job states without mutating the batch membership
- bulk retry returns failed or `retry_pending` jobs to normal queued execution
  when they are still eligible and uniqueness-safe
- bulk cancellation can stop queued, retry-pending, reserved, or running jobs;
  active leases are invalidated so stale worker acknowledgments cannot win
- queue pause affects reservation only; existing queued jobs stay queued,
  active work keeps its current lease, and resume makes the queue eligible
  again
- dead-letter actions isolate explicit job ids, replay isolated work to
  `queued`, schedule controlled retry through `retry_pending`, or discard to
  `cancelled`

Selector-based mass mutation, approval workflow, and audit policy remain
higher-level operator and governance concerns.

### Inspecting A Running Worker Runtime

The supervisor-managed worker runtime surfaces:

- supervisor topology inspection
- coarse child-process and worker-thread state visibility
- graceful drain and force-stop controls at the whole-supervisor level
- local CLI access through a runtime state file plus a supervisor-owned Unix
  control socket validated with an instance token
- reliability inspection showing when queued work is blocked by breaker-open
  behavior versus capacity or routing constraints
- queue-control inspection showing whether reservation is intentionally paused
  for a queue
- corresponding dashboard and operator API workflows that expose the same
  runtime vocabulary for investigation and intervention

Runtime control remains aligned around the supervisor-managed execution model:
supervisor state, child-process state, worker-thread state, and safe
intervention boundaries around queued, reserved, running, retry, isolation, and
recovery flows.

## Related Concepts

- [Workers](/runtime/workers/): runtime controls supervise active execution
- [Retries](/reliability/retries/): recovery actions extend the same control
  model
- [Dead Letters](/reliability/dead-letters/): isolation and governed recovery
  use the same control vocabulary
- [CLI](/operator/cli/): command workflows mirror the runtime control model
- [Troubleshooting](/troubleshooting/): use control surfaces during triage
