---
title: Getting Started
nav_order: 3
permalink: /getting-started/
---

# Getting Started

Use this path when evaluating Karya, developing inside the monorepo, or
standing up a framework host with the shared dashboard.

If you are new to the project, this page is the fastest path from checkout to a
working mental model of how Karya fits together.

## Repository Setup

From the repository root:

```bash
scripts/ci-install-bundles
scripts/run-all
```

These scripts install Ruby and dashboard dependencies across the monorepo and
run the shared verification flow.

## Evaluation Path

1. Read the [Architecture](architecture.md) page for the package map and
   platform boundaries.
2. Choose a backend using [Backends](backends.md). Postgres is the default
   production recommendation.
3. Choose a host integration from [Frameworks](frameworks/index.md).
4. Review [Dashboard Hosting](host-workflow.md) if you want a framework host to
   include the optional dashboard addon.
5. Review [Adoption](adoption/index.md) if you are coming from Sidekiq,
   GoodJob, Solid Queue, or ActiveJob.

## Local Dashboard Work

For focused dashboard development:

```bash
scripts/run-dashboard-dev
```

For packaged asset verification inside `gems/karya-dashboard`:

```bash
bin/build
bin/prepackage-build
```

## Recommended Starting Defaults

- host: use the framework package that matches your application stack
- backend: start with Postgres unless a documented constraint points elsewhere
- scheduler: use the built-in Kaal-backed recurring-job subsystem
- operator surface: treat the dashboard, API, and CLI as complementary rather
  than choosing only one

## Before Going To Production

Review these sections before adopting Karya in a production environment:

- [Reliability](reliability/index.md)
- [Workflows](workflows/index.md)
- [Observability](observability.md)
- [Governance](governance/index.md)
- [Troubleshooting](troubleshooting.md)
