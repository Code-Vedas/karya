---
title: Observability
nav_order: 11
---

# Observability

Karya documents observability as a first-class operating contract rather than an
optional addon.

You should be able to explain what Karya is doing from traces, logs, metrics,
and health surfaces without reverse-engineering the runtime.

Observability is part of the product story because operators need to move
cleanly between external monitoring, the Karya dashboard, and governed recovery
workflows.

## Supported Signals

- OpenTelemetry instrumentation
- structured logs
- Prometheus/OpenMetrics-compatible metrics export
- W3C Trace Context-style propagation
- health and readiness surfaces for automation and orchestration

## Why It Matters

Karya spans queue execution, workflows, schedules, dashboard operations, and
governed production controls. Observability is what ties those surfaces
together when something slows down, fails, or needs explanation.

## How Signals Relate To Operator Work

Observability data supports:

- dashboard summary and drilldown context
- operator API-driven troubleshooting
- external monitoring, alerting, and trace analysis
- correlation between runtime execution, workflow state, and governed actions

## What Good Observability Looks Like

Good observability in Karya means:

- a queue slowdown can be seen in metrics and confirmed in the operator surface
- a workflow failure can be traced through runtime history and external tracing
- operator actions such as replay, pause, or rollback remain visible in logs and
  audit-oriented timelines
- health and readiness surfaces make host-level automation trustworthy

## Documentation Guidance

When integrating Karya into a host application:

- emit traces consistently through the shared context propagation model
- use structured logs so queue, workflow, and policy events remain queryable
- expose metrics in the same environment where the dashboard and operators can
  correlate behavior
- include health and readiness checks in operational automation

## Common Scenarios

### Investigating A Slow Queue

```text
signal: queue depth rising
follow-up: inspect queue metrics and worker activity
operator view: drill into queue and worker detail
goal: confirm whether the issue is throughput, limits, or paused execution
```

This is where metrics, worker state, and operator drilldowns should tell the
same story.

### Explaining A Workflow Failure

```text
signal: workflow marked failed
follow-up: inspect timeline, traces, and structured logs
operator view: review replay or compensation options
goal: understand failure cause before taking recovery action
```

This is where observability stops being passive telemetry and becomes part of
recovery.

### Validating Host Health

```text
signal: readiness degraded
follow-up: inspect host health surface and operator signals
goal: determine whether the issue is local startup, backend access, or workload pressure
```

Health and readiness checks matter most when they line up with what operators
and automation see elsewhere.

## Standards-Facing Integrations

Karya also documents standards-aware integration around:

- CloudEvents-compatible outbound events
- webhook signing conventions for external consumers
- error envelope and pagination conventions on operator-facing APIs

## Related Concepts

- [Operator](operator/index.md): use dashboard, internal API, and CLI surfaces
  alongside observability data
- [Runtime](runtime/index.md): understand what the runtime emits and why
- [Workflows](workflows/index.md): connect execution history to trace and log
  analysis
- [Governance](governance/index.md): keep operator actions, approvals, and
  rollout behavior observable
- [Troubleshooting](troubleshooting.md): use these signals to move from symptom
  to root cause
