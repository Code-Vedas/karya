---
title: Tenant Isolation
parent: Governance
nav_order: 3
permalink: /governance/tenant-isolation/
---

# Tenant Isolation

Tenant and namespace boundaries affect more than storage. They also shape
operator visibility and control.

## Covered Behavior

- tenant-aware search and metrics boundaries
- quotas and limits
- visibility scoping
- destructive-action safeguards in multi-tenant environments

## Common Scenarios

### Verifying Tenant Boundaries

Tenant boundaries should show up in operator visibility and limits:

```text
tenant: north-america
queue: billing
visible_jobs: 124
quota_status: within-limit
cross-tenant-access: denied
```

Tenant isolation affects what an operator can see and do, not only how data is
stored.

## Related Concepts

- [Policies](policies.md): tenant boundaries often shape policy outcomes
- [Search And Drilldowns](../operator/search-drilldowns.md): search must respect
  tenant scope
- [Backends](../backends.md): backend choice still has to preserve isolation
