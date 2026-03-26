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

- minimal runtime inspection APIs
- queue and worker lifecycle control
- bulk enqueue, retry, cancel, and pause/resume operations
- operator-visible state used for safe intervention

## Surface Model

- dashboard: live investigation and operator action
- operator API: integration and automation
- CLI: local operations and scripted control

## Relationship To Other Sections

Runtime controls define the safe entrypoints. Reliability, workflow, and
governance features extend those same control boundaries rather than creating
separate operational models.

## Common Scenarios

### Taking A Runtime Action

Runtime controls should read consistently across UI, API, and CLI surfaces:

```text
pause queue billing
resume queue billing
retry failed job <job-id>
inspect worker <worker-id>
```

Command and API shapes may evolve, but the model stays the same: operators can
inspect and intervene through aligned surfaces instead of learning unrelated
control models.

## Related Concepts

- [Workers](workers.md): runtime controls supervise active execution
- [Retries](../reliability/retries.md): recovery actions extend the same control
  model
- [CLI](../operator/cli.md): command workflows mirror the runtime control model
- [Troubleshooting](../troubleshooting.md): use control surfaces during triage
