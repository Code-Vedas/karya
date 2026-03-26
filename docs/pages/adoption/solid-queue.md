---
title: Solid Queue
parent: Adoption
nav_order: 3
permalink: /adoption/solid-queue/
---

# Solid Queue

Solid Queue users often have the cleanest path through Rails and ActiveJob.

## Guidance

- begin with the Rails and ActiveJob compatibility path
- map queue execution to the Karya runtime model
- plan for workflow, governance, and operator-surface expansion during rollout

## Common Scenarios

### Starting From Rails And ActiveJob

Solid Queue teams often start from the Rails host and expand from there:

```text
current_system: solid-queue
host: rails
compatibility_path: activejob
next_step: adopt karya runtime controls and operator surfaces
```

This is a staged path, not a one-shot migration.

## Related Concepts

- [Rails](../frameworks/rails.md): the host integration usually anchors this
  move
- [ActiveJob](../frameworks/activejob.md): compatibility is part of the staged
  adoption story
- [Rollout](../governance/rollout.md): production rollout still needs control
