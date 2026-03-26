---
title: Karya
nav_order: 1
permalink: /
description: Karya platform overview and documentation entrypoint.
---

# Karya

{: .note }
> Karya is in early development and is extremely unstable. Expect breaking changes and a lack of documentation until the 1.0 release.

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

1. [Getting Started](pages/getting-started.md)
2. [Architecture](pages/architecture.md)
3. [Runtime](pages/runtime/index.md)
4. [Backends](pages/backends.md)
5. [Frameworks](pages/frameworks/index.md)
6. [Dashboard Hosting](pages/host-workflow.md)
7. [Adoption](pages/adoption/index.md)

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

- [Architecture](pages/architecture.md): package map, capability model, and how
  the platform fits together
- [Getting Started](pages/getting-started.md): setup path for repository work
  and initial platform evaluation
- [Runtime](pages/runtime/index.md): job model, workers, control surfaces, and
  execution semantics
- [Reliability](pages/reliability/index.md): retries, uniqueness, dead letters,
  and backpressure
- [Workflows](pages/workflows/index.md): orchestration, replay, signals, child
  workflows, and versioning
- [Backends](pages/backends.md): selection guidance, tiers, and capability
  matrix
- [Frameworks](pages/frameworks/index.md): host integrations, ActiveJob, and
  parity notes
- [Dashboard Hosting](pages/host-workflow.md): packaged asset contract and host
  responsibilities
- [Operator](pages/operator/index.md): dashboard, internal API, CLI, search,
  and audit workflows
- [Observability](pages/observability.md): traces, metrics, logs, and health
  surfaces
- [Governance](pages/governance/index.md): identity, policies, tenant
  boundaries, rollout controls, and retention guidance
- [Adoption](pages/adoption/index.md): Sidekiq, GoodJob, Solid Queue, and
  cutover guidance
- [Troubleshooting](pages/troubleshooting.md): setup, runtime, hosting, and
  operator problem-solving
- [Development](pages/development.md): repository workflows and package-local
  development
