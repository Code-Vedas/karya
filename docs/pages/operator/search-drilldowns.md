---
title: Search And Drilldowns
parent: Operator
nav_order: 4
---

# Search And Drilldowns

Karya documents search, filtering, saved views, and drilldowns as first-class
operator workflows.

## Covered Behavior

- advanced filtering and sorting
- saved views
- drilldowns from summary surfaces into queue, worker, workflow, and schedule
  detail views
- API-aligned filtering and pagination conventions

## Common Scenarios

### Reusing An Investigation

Operators need to save and reuse common investigations:

```text
saved_view: failed-payments-last-24h
filters:
  queue: billing
  status: failed
  updated_within: 24h
drilldown: workflow detail
```

Search is not separate from action. It is the entrypoint into inspection and
recovery.

## Related Concepts

- [Dashboard](dashboard.md): search starts from the operator UI
- [Activity And Audit](activity-audit.md): investigation often ends in action or
  audit review
- [Backpressure](../reliability/backpressure.md): queue pressure is a common
  drilldown trigger
