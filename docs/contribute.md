---
title: Contribute
nav_order: 120
permalink: /contribute/
---

# Contribute

## Basic Flow

1. Fork the repository.
2. Clone your fork and create a branch.
3. Install dependencies for the packages you are changing.
4. Make the change.
5. Run the relevant checks.
6. Push and open a pull request.

## Monorepo Structure

- `gems/karya`
  Core runtime, queue store contracts, workflows, CLI primitives, and shared
  internal support.
- `gems/karya-rails`
  Rails integration.
- `gems/karya-hanami`
  Hanami integration.
- `gems/karya-roda`
  Roda integration.
- `gems/karya-sinatra`
  Sinatra integration.
- `gems/karya-dashboard`
  Dashboard frontend package.
- `docs/`
  Docs site source.
- `scripts/`
  Repo-level verification helpers.

## Root Checks

Run these from the repo root:

```bash
scripts/run-rubocop-all
scripts/run-reek-all
scripts/run-rbs-all
scripts/run-rspec-unit-all
scripts/run-rspec-e2e-all
scripts/run-prepackage-build-all
```

Or run the full monorepo verification flow:

```bash
scripts/run-all
```

## Package-Level Checks

Core runtime work usually starts here:

```bash
cd gems/karya
bin/rubocop
bin/reek
bin/rspec-unit
rbs -I sig validate
```

Framework packages expose similar package-local checks:

```bash
cd gems/karya-rails
bin/rubocop
bin/reek
bin/rspec-unit
```

## Docs Contributions

Treat `docs/` as future-state product documentation. When reviewing docs, check
product behavior, names, flows, examples, contradictions, stale references, and
broken paths, but do not downgrade the documentation because future-state code
is not present yet.

## Useful Contributions

- worker/runtime improvements
- backend and durability fixes
- framework integration refinements
- workflow modeling and recovery improvements
- docs and examples
- test coverage and CI hardening
