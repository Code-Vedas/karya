---
title: Karya
nav_order: 1
permalink: /
description: Karya platform overview and documentation entrypoint.
---

# Karya

{: .note }

> Karya is in early development and is extremely unstable. Expect breaking changes and frequent updates to both APIs and documentation until the 1.0 release.

Karya is a Ruby-first background job and workflow platform that combines
durable execution, workflow orchestration, framework-native integration, and a
shared operator experience.

It gives teams one operational model for application jobs, long-running
workflows, framework hosts, operator tooling, and governed production rollout.

## What The Platform Includes

- a canonical runtime and CLI
- backend adapters with an explicit capability matrix
- first-class integrations for plain Ruby, Rails, Sinatra, Roda, and Hanami
- ActiveJob compatibility and migration guidance
- an optional dashboard addon with shared UI delivery, internal APIs, and Kaal
  operator surfaces across frameworks
- recurring scheduling through Kaal
- operator APIs, CLI commands, and governance-oriented control surfaces
- observability, standards-facing integration contracts, and adoption playbooks

## Recommended Reading Path

1. [Getting Started](/getting-started/)
2. [Architecture](/architecture/)
3. [Runtime](/runtime/)
4. [Backends](/backends/)
5. [Frameworks](/frameworks/)
6. [Dashboard Hosting](/dashboard-hosting/)
7. [Adoption](/adoption/)

## Support Snapshot

| Area                          | Position                                                                  |
| ----------------------------- | ------------------------------------------------------------------------- |
| Default production backend    | Postgres                                                                  |
| Additional supported backends | Redis, MySQL, SQLite                                                      |
| Local/dev backend             | `InMemory`                                                                |
| First-class hosts             | plain Ruby, Rails, Sinatra, Roda, Hanami                                  |
| Compatibility path            | ActiveJob                                                                 |
| Scheduler                     | Kaal-backed recurring job and cron subsystem                              |
| Operator surfaces             | dashboard UI, dashboard internal APIs, operator APIs, CLI                 |
| Identity standards            | OIDC/OAuth2 and SAML                                                      |
| Observability standards       | OpenTelemetry, structured logs, Prometheus/OpenMetrics, W3C Trace Context |
| Eventing standards            | CloudEvents-compatible outbound events                                    |

## Explore The Docs

- [Architecture](/architecture/): package map, capability model, and how
  the platform fits together
- [Getting Started](/getting-started/): setup path for repository work
  and initial platform evaluation
- [Runtime](/runtime/): job model, workers, control surfaces, and
  execution semantics
- [Reliability](/reliability/): retries, uniqueness, dead-letter isolation,
  governed recovery, and backpressure
- [Workflows](/workflows/): orchestration, replay, signals, child
  workflows, and versioning
- [Backends](/backends/): selection guidance, tiers, and capability
  matrix
- [Frameworks](/frameworks/): host integrations, ActiveJob, and
  parity notes
- [Dashboard Hosting](/dashboard-hosting/): packaged asset contract and host
  responsibilities
- [Operator](/operator/): dashboard, internal API, CLI, search,
  and audit workflows
- [Observability](/observability/): traces, metrics, logs, and health
  surfaces
- [Governance](/governance/): identity, policies, tenant
  boundaries, rollout controls, and retention guidance
- [Adoption](/adoption/): Sidekiq, GoodJob, Solid Queue, and
  cutover guidance
- [Troubleshooting](/troubleshooting/): setup, runtime, hosting, and
  operator problem-solving
- [Development](/development/): repository workflows and package-local
  development
