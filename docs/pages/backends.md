---
title: Backends
nav_order: 7
permalink: /backends/
---

# Backends

Backend choice shapes durability, operator workflows, scheduling behavior,
failure recovery, and the overall fit between Karya and the rest of the stack.
This page helps teams make that choice with intent.

Karya supports both local development backends and production backends, but
they are not interchangeable. The right choice depends on whether the goal is
fast local iteration, production-like local evaluation, or a durable
production deployment.

## Backend Positions

| Backend    | Position                      | Typical Fit                                       |
| ---------- | ----------------------------- | ------------------------------------------------- |
| `InMemory` | Local quick-start backend     | Fast examples, tests, and local development       |
| SQLite     | Local production-like backend | Local SQL-backed evaluation                       |
| Redis      | Production backend            | Production use                                    |
| Postgres   | Production backend            | Production use                                    |
| MySQL      | Production backend            | Production use                                    |

## Support Boundaries

- Use `InMemory` for local testing, examples, and development speed.
- Use SQLite when you want a local backend that feels closer to a real SQL
  deployment.
- Use Redis, Postgres, or MySQL for production deployments.
- Do not use `InMemory` in production.
- Do not use SQLite in production.

## How To Choose

Choose `Karya::Backend::InMemory` when:

- you want the fastest possible setup
- you are testing locally
- you are building examples
- you do not need durability across restarts or processes

Choose SQLite when:

- you want a local SQL-backed runtime
- you want a production-like local development path
- you are validating SQL-oriented behavior before moving to a production
  backend
- the deployment is intentionally local or single-node

Choose Redis when:

- you want a production backend
- Redis is the backend you intend to operate

Choose Postgres when:

- you want a production backend
- Postgres is the backend you intend to operate

Choose MySQL when:

- you want a production backend
- MySQL is the backend you intend to operate

## What Backends Influence

Backend choice affects more than persistence:

- how operators reason about queue depth, recovery, and history
- how workflows and schedules remain durable across process or host failures
- what adapter path and operational posture fit the deployment best
- what troubleshooting guidance applies in production

## Common Scenarios

### General-Purpose Production Platform

```text
host: rails
backend: Karya::Backend::Postgres
goal: durable jobs, workflows, schedules, and operator visibility
recommendation: production deployment
```

This fits teams that want durable orchestration and a long-lived operator
surface.

### Existing Queue-Centric Runtime

```text
host: plain-ruby
backend: Karya::Backend::Redis
goal: high-throughput queue execution with strong operational monitoring
recommendation: production deployment
```

This fits teams that already operate Redis heavily and want Karya to align with
that environment.

### Local Development Or Examples

```text
host: plain-ruby
backend: Karya::Backend::InMemory
goal: fast setup, tests, examples
recommendation: local/dev/test only
```

This is for speed and simplicity, not as a production durability story.

### Production-Like Local SQL Evaluation

```text
host: rails
backend: Karya::Backend::SQLite
goal: local SQL-backed evaluation before production rollout
recommendation: local only, production-like development path
```

This fits teams that want local SQL behavior without treating the local backend
as the production deployment target.

## Adapter Pairings

- Active Record path: choose a backend class that fits the SQL/runtime model
- Sequel path: choose a backend class that fits the host and persistence model
- plain Ruby: compose the backend class and persistence adapter that fit the
  selected deployment model

## Related Concepts

- [Frameworks](/frameworks/): choose the host integration that matches
  the backend path
- [Reliability](/reliability/): understand how backend behavior shapes
  recovery and backpressure
- [Workflows](/workflows/): see why durable orchestration changes the
  backend conversation
- [Troubleshooting](/troubleshooting/): use backend-specific debugging guidance
  when production behavior diverges
- [Governance](/governance/): review retention, audit, and rollout needs
  before finalizing the backend choice
