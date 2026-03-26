---
title: Rollout
parent: Governance
nav_order: 4
---

# Rollout

Karya documents governed rollout rather than treating production change
management as an external concern.

## Covered Behavior

- governed cutover and rollback guidance
- rollout approvals
- release-channel controls
- versioning, deprecation, and upgrade policy posture

## Common Scenarios

### Releasing A New Capability Safely

Rollout controls should make change state explicit:

```text
release_channel: canary
target_feature: workflow-v2
approval_state: pending
rollback_path: available
```

Rollout behavior stays intentional and operator-visible rather than ad hoc.

## Related Concepts

- [Policies](policies.md): approvals and release controls must agree
- [Versioning](../workflows/versioning.md): workflow evolution and rollout are
  tightly connected
- [Cutover And Rollback](../adoption/cutover-rollback.md): rollout controls feed
  directly into production adoption
