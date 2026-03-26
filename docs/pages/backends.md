---
title: Backends
nav_order: 7
permalink: /backends/
---

# Backends

Karya documents backend support through an explicit capability matrix instead of
implying parity from package names alone.

Backend choice shapes durability, operator workflows, scheduling behavior,
failure recovery, and the overall fit between Karya and the rest of the stack.
This page helps teams make that choice with intent.

## Recommended Default

Postgres is the default production recommendation for teams that do not already
have a stronger operational preference.

For most teams, Postgres is the easiest recommendation to defend: it fits the
broader Karya product model, works well with framework integrations, and gives
operators one durable system of record for execution and orchestration state.

## Support Matrix

| Backend    | Position                      | Typical Fit                                            |
| ---------- | ----------------------------- | ------------------------------------------------------ |
| Postgres   | Default production backend    | General-purpose production deployments                 |
| Redis      | Supported production backend  | Queue-centric, low-latency operational workloads       |
| MySQL      | Supported production backend  | SQL environments standardized on MySQL                 |
| SQLite     | Supported constrained backend | Embedded, single-node, or lightweight SQL deployments  |
| `InMemory` | Local/dev/test backend        | Examples, development, tests, and ephemeral evaluation |

## How To Choose

Choose Postgres when:

- you want the default production path
- you expect workflows, schedules, audit history, and operator workflows to
  matter from the beginning
- you want the broadest fit across hosts and future backlog capability

Choose Redis when:

- you are optimizing for queue-centric throughput and low-latency operational
  behavior
- your team already runs Redis as a core infrastructure dependency
- you are comfortable reviewing backend-specific caveats as the product surface
  expands

Choose MySQL when:

- production standards already center on MySQL
- you want a supported SQL-backed path without introducing Postgres

Choose SQLite when:

- the deployment is intentionally small, embedded, or single-node
- the operational tradeoffs are acceptable and clearly understood

Choose `InMemory` when:

- you are developing locally
- you need quick examples or tests
- durability and multi-process production behavior are not part of the goal

## Capability Expectations

The documented backend contract covers parity for:

- job and queue persistence
- workflow and batch state
- schedules and recurring-job state
- audit-relevant and operator-visible history
- capability reporting and intentional parity exceptions

## What Backends Influence

Backend choice affects more than persistence:

- how operators reason about queue depth, recovery, and history
- how workflows and schedules remain durable across process or host failures
- what parity guarantees can be treated as universal versus backend-specific
- what troubleshooting guidance applies in production

## Unsupported Or Tiered Cases

When a backend has different scale, durability, or concurrency tradeoffs, the
docs call that out explicitly. `InMemory` is documented as a non-primary backend
for local/dev/test usage rather than a peer production recommendation.

## Common Scenarios

### General-Purpose Production Platform

```text
host: rails
backend: postgres
goal: durable jobs, workflows, schedules, and operator visibility
recommendation: default production path
```

This is the baseline recommendation for teams adopting Karya as a long-term
platform rather than a narrow queue runner.

### Existing Queue-Centric Runtime

```text
host: plain-ruby
backend: redis
goal: high-throughput queue execution with strong operational monitoring
recommendation: supported, with explicit review of parity caveats
```

This fits teams that already operate Redis heavily and want Karya to align with
that environment.

### Local Development Or Examples

```text
host: plain-ruby
backend: InMemory
goal: fast setup, tests, examples
recommendation: local/dev/test only
```

This is for speed and simplicity, not as a production durability story.

## Adapter Pairings

- Active Record path: typically Rails with `core/karya-activerecord`
- Sequel path: Hanami, Roda, and Sinatra with `core/karya-sequel`
- plain Ruby: choose the adapter path that matches the selected backend and
  persistence style

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
