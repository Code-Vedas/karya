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

## Documentation Workflow

The docs site under `docs/` is the source of truth for:

- support matrices
- framework and backend guidance
- operator and governance documentation
- migration and troubleshooting guidance

Keep package READMEs concise and consistent with the central docs site.
