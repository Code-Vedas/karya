---
title: Dashboard
parent: Operator
nav_order: 1
permalink: /operator/dashboard/
---

# Dashboard

The dashboard is the robust operator UI shipped by the optional
`karya-dashboard` addon.

## Covered Behavior

- queue, worker, workflow, and schedule views
- Kaal-facing recurring-job workflows
- shared asset delivery across frameworks
- responsive and accessibility-aware operator UX

## Common Scenarios

### Moving From Summary To Action

The dashboard should let an operator move from summary to action:

```text
dashboard widget: queued jobs
selected queue: billing
drilldown opened: queue detail
available actions: inspect, pause, resume
```

The flow matters: summary context leads straight into actionable operator
detail.

## Related Concepts

- [Search And Drilldowns](search-drilldowns.md): drilldowns turn summary into
  investigation
- [Activity And Audit](activity-audit.md): actions taken from the dashboard must
  stay visible later
- [Dashboard Hosting](../host-workflow.md): the UI depends on correct delivery
