---
title: Backends
nav_order: 7
permalink: /backends/
---

# Backends

Backend choice shapes durability, operator workflows, scheduling behavior,
failure recovery, and the overall fit between Karya and the rest of the stack.
This page helps teams make that choice with intent.

Karya supports local backends for development and shared backends for durable
deployments. Backend choice is an operational decision: where state lives, what
survives process restarts, and what infrastructure the team is prepared to run.

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

Add the SQLite client gem before configuring the backend:

```ruby
# Gemfile
gem 'sqlite3', '~> 2.6'
```

```ruby
Karya.configure_backend(
  Karya::Backend::SQLite,
  url: 'sqlite3:///tmp/karya.sqlite3',
  namespace: 'karya'
)
```

Choose Redis when:

- worker processes must share queue and workflow state through Redis
- jobs and workflows must survive worker restarts
- the deployment already uses Redis as shared runtime infrastructure

Add the Redis client gem before configuring the backend:

```ruby
# Gemfile
gem 'redis', '~> 5.4'
```

```ruby
Karya.configure_backend(
  Karya::Backend::Redis,
  url: 'redis://127.0.0.1:6379/0',
  namespace: 'karya'
)
```

Redis-backed queue-store persistence rejects job arguments containing `Symbol`
values or non-finite `Float` values (`Float::NAN`, `Float::INFINITY`, and
`-Float::INFINITY`). Normalize those payload values before enqueueing jobs that
must persist through Redis. Redis-backed persistence also requires
`Karya::JobLifecycle::Registry` lifecycles; jobs using other lifecycle
implementations must normalize to a registry-backed lifecycle before enqueue.

Choose Postgres when:

- worker processes must share durable state through PostgreSQL
- the deployment is centered on PostgreSQL operations
- queue, workflow, and operator state should live in the primary SQL system

Choose MySQL when:

- worker processes must share durable state through MySQL
- the deployment is centered on MySQL operations
- queue, workflow, and operator state should live in the primary SQL system

Add the MySQL client gem before configuring the backend:

```ruby
# Gemfile
gem 'mysql2', '~> 0.5'
```

```ruby
Karya.configure_backend(
  Karya::Backend::MySQL,
  url: 'mysql2://app:secret@127.0.0.1:3306/karya',
  namespace: 'karya'
)
```

## What Backends Influence

Backend choice affects more than persistence:

- how operators reason about queue depth, recovery, and history
- how workflows and schedules remain durable across process or host failures
- what adapter path and operational posture fit the deployment best
- what troubleshooting guidance applies in production

Configure Karya with a backend class and the backend options required for that
deployment. Karya uses the backend to initialize the queue store used by
workers and supervisors.

## Common Scenarios

### General-Purpose Production Platform

```text
host: rails
backend: postgres
goal: durable jobs, workflows, schedules, and operator visibility
recommendation: production deployment
```

This fits teams that want durable orchestration and a long-lived operator
surface.

### Existing Queue-Centric Runtime

```text
host: plain-ruby
backend: redis
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
backend: sqlite
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
