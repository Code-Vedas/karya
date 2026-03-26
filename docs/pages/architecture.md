---
title: Architecture
nav_order: 2
---

# Architecture

Karya is organized as a monorepo, but the product surface is intentionally
split into composable packages with stable responsibilities.

That split is deliberate: the runtime, adapters, framework hosts, dashboard,
and operator surfaces each have a clear role and are meant to compose cleanly.

## Package Map

| Package                   | Role                                                                          |
| ------------------------- | ----------------------------------------------------------------------------- |
| `core/karya`              | Core runtime, CLI, execution model, workflow engine, and shared contracts     |
| `core/karya-activerecord` | Active Record adapter for SQL-oriented hosts                                  |
| `core/karya-sequel`       | Sequel adapter for SQL-oriented hosts                                         |
| `gems/karya-dashboard`    | Optional dashboard addon with shared UI, internal APIs, and rendering helpers |
| `gems/karya-rails`        | Rails host integration                                                        |
| `gems/karya-hanami`       | Hanami host integration                                                       |
| `gems/karya-roda`         | Roda host integration                                                         |
| `gems/karya-sinatra`      | Sinatra host integration                                                      |

## Capability Model

Karya’s product model is built from these layers:

1. Runtime execution: jobs, queues, workers, controls, lifecycle, and recovery.
2. Reliability: routing, retries, backoff, rate limits, uniqueness, fairness,
   dead-letter isolation, and recovery automation.
3. Orchestration: workflows, batch execution, signals, child workflows,
   approval checkpoints, replay, and version evolution.
4. Persistence: backend adapters, capability reporting, parity guarantees, and
   documented exceptions.
5. Framework integration: host-native mounting, auth/session alignment, adapter
   pairing, and operator API exposure.
6. Operator experience: dashboard, APIs, CLI, search, drilldowns, activity,
   audit, and bulk actions.
7. Governance and standards: identity, policies, rollout controls, observability,
   eventing, and compliance-oriented data handling.

## Operator Surface Model

The product exposes three peer operator surfaces:

- dashboard UI for live operational investigation and action
- operator APIs for automation and systems integration
- CLI commands for scripting, local operations, and controlled lifecycle tasks

All three surfaces share the same domain vocabulary: queues, workers,
workflows, schedules, activity, policies, approvals, and rollout state.

## Scheduling Model

Recurring jobs and cron-style schedules are provided through the Kaal-backed
scheduling subsystem. When the dashboard addon is included, it also surfaces
Kaal-backed scheduling workflows through the operator UI and internal API
contracts.

## Standards-Facing Posture

Karya documents standards-facing compatibility for:

- OpenTelemetry traces and span propagation
- structured logs
- Prometheus/OpenMetrics-compatible metrics
- W3C Trace Context-style propagation
- CloudEvents-compatible outbound events
- OIDC/OAuth2 and SAML identity integration

These are part of the supported product surface because operator tooling,
external integrations, and governance workflows depend on them.

## Documentation Map

- [Runtime](runtime/index.md)
- [Reliability](reliability/index.md)
- [Workflows](workflows/index.md)
- [Frameworks](frameworks/index.md)
- [Operator](operator/index.md)
- [Governance](governance/index.md)
- [Adoption](adoption/index.md)
