---
title: Development
nav_order: 15
permalink: /development/
---

# Development

This repository is organized as a multi-package Ruby and Node workspace with a
shared verification flow.

## Repository Workflow

From the repository root:

```bash
scripts/ci-install-bundles
scripts/run-all
```

The shared scripts coordinate repository-wide verification across the Ruby
packages and the dashboard frontend.

## Package-Local Workflow

Each package README documents its local commands. Typical package checks include:

- `bin/rspec-unit`
- `bin/rspec-e2e`
- `bin/rubocop`
- `bin/reek`

Dashboard work additionally uses:

- `bin/dev`
- `bin/build`
- `bin/prepackage-build`
- `bin/firefox-e2e`

## RBS And Internals

`core/karya` uses RBS as a whole-implementation correctness contract. Public
runtime types and internal implementation helpers should both stay true to the
Ruby code they describe.

Shared internal helpers belong under `Karya::Internal`, with Ruby files under
`core/karya/lib/karya/internal/` and signatures under
`core/karya/sig/karya/internal/`. These constants are visible for runtime
wiring, but they are not supported public API. Owner-local helpers can remain
nested under their owning class or module and may be typed inside that owner’s
RBS file instead of having a one-to-one file mapping.

## Unit Spec Mirroring

When `core/karya` code is split into responsibility-named owner-local files,
prefer mirrored unit specs under `core/karya/spec/` for those files. Keep large
owner specs focused on public API behavior, orchestration, and integration
flows, while direct helper behavior lives beside the mirrored unit spec.

## Documentation Workflow

The docs site under `docs/` is the source of truth for:

- support matrices
- framework and backend guidance
- operator and governance documentation
- migration and troubleshooting guidance

Keep package READMEs concise and consistent with the central docs site.
