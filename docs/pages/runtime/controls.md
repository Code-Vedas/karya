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
- retry, isolation, replay, and governed recovery actions across aligned
  operator surfaces
- breaker-open, half-open, and stuck-work inspection vocabulary for unhealthy
  execution paths
- operator-visible state used for safe intervention across `queued`,
  `reserved`, `running`, `failed`, `retry_pending`, `cancelled`, and extension
  states such as `dead_letter` when they are registered

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
dashboard action: inspect dead_letter job <job-id>
dashboard action: inspect circuit_breaker queue:billing
operator API action: replay isolated job <job-id>
CLI action: karya runtime inspect --state-file /tmp/karya-runtime-billing.json
```

Dashboard, operator API, and CLI workflows use the same runtime vocabulary for
inspection and intervention.

### Inspecting A Running Worker Runtime

The supervisor-managed worker runtime surfaces:

- supervisor topology inspection
- coarse child-process and worker-thread state visibility
- graceful drain and force-stop controls at the whole-supervisor level
- local CLI access through a runtime state file plus a supervisor-owned Unix
  control socket validated with an instance token
- reliability inspection showing when queued work is blocked by breaker-open
  behavior versus capacity or routing constraints
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
