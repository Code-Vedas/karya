---
title: Internal API
parent: Operator
nav_order: 2
permalink: /operator/internal-api/
---

# Internal API

The dashboard addon also ships the internal API surface consumed by the robust
operator UI.

## Position

- owned by the dashboard addon
- mounted by framework hosts that include `karya-dashboard`
- aligned with the same domain vocabulary as the dashboard, operator API, and
  CLI

## Covered Behavior

- dashboard data loading
- operator workflow actions initiated by the UI
- recurring schedule and Kaal-facing interactions

## Common Scenarios

### Loading Dashboard Detail

The internal API exists to support the dashboard-owned workflows:

```text
request: load queue detail for billing
response: queue summary, worker state, pending jobs, available actions
```

The dashboard depends on an internal API that speaks the same operator
vocabulary as the rest of the product.

## Related Concepts

- [Dashboard](/operator/dashboard/): the UI is the main consumer of this API
- [CLI](/operator/cli/): keep the operator vocabulary aligned across surfaces
- [Observability](/observability/): internal API behavior still needs to be
  observable
