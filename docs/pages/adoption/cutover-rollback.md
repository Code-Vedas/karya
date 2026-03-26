---
title: Cutover And Rollback
parent: Adoption
nav_order: 4
permalink: /adoption/cutover-rollback/
---

# Cutover And Rollback

Production adoption should include explicit cutover and rollback planning.

## Covered Behavior

- staged rollout
- operator readiness before cutover
- rollback expectations
- alignment with governed rollout controls and approval paths

## Common Scenarios

### Preparing A Controlled Release

Cutover planning should make the transition state explicit:

```text
phase: canary
traffic_split: partial
operator_readiness: verified
rollback_status: ready
```

Production adoption is a governed transition, not just a package installation
step.

## Related Concepts

- [Rollout](../governance/rollout.md): cutover planning depends on rollout
  controls
- [Versioning](../workflows/versioning.md): workflow evolution affects rollback
  safety
- [Activity And Audit](../operator/activity-audit.md): operators need clear
  release history during transition
