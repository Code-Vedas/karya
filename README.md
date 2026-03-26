# Karya

> Karya is in early development and is extremely unstable. Expect breaking changes and a lack of documentation until the 1.0 release.

`Karya` is a monorepo for the core Karya runtime, adapter gems, framework integrations,
the dashboard UI gem, and the documentation site.

## Current foundation

The repository currently includes:

- `core/karya` for the canonical CLI and shared runtime
- `core/karya-activerecord` and `core/karya-sequel` for datastore adapters
- `gems/karya-dashboard` for the React, TypeScript, Tailwind, and Playwright UI package
- `gems/karya-hanami`, `gems/karya-rails`, `gems/karya-roda`, and `gems/karya-sinatra`
  for framework integration scaffolds
- root scripts that run lint, unit, e2e, build, prepackage, and Firefox browser checks

## Local workflow

Install all package dependencies and run the shared verification flow from the
repository root:

```bash
scripts/ci-install-bundles
scripts/run-all
```

The dashboard dev server can be started with:

```bash
scripts/run-dashboard-dev
```

## Dashboard distribution contract

`gems/karya-dashboard` publishes a packaged bundle under `dist/`:

- `dist/index.html` as the packaged HTML entrypoint
- `dist/assets/*` for hashed JS and CSS output
- `dist/asset-manifest.json` as the packaged asset manifest
