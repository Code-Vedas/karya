# Karya

> Karya is in early development and is extremely unstable. Expect breaking changes and rapidly evolving documentation until the 1.0 release.

Karya is a Ruby-first background job and workflow platform for teams that want
one runtime model across application jobs, durable workflows, framework
integrations, and operator tooling.

The monorepo contains the core runtime, backend adapters, framework packages,
the packaged dashboard frontend, and the documentation site.

## Why Karya

Karya brings the operational surfaces that Ruby teams usually assemble from
multiple tools into one platform:

- durable job execution with explicit routing, retries, backpressure, recovery,
  and dead-letter handling
- workflow orchestration with replay, compensation, child workflows, signals,
  queries, approval checkpoints, and versioning
- framework-native integration for plain Ruby, Rails, Sinatra, Roda, and Hanami
- a shared operator experience spanning dashboard UI, operator APIs, and CLI
- backend flexibility across Postgres, Redis, MySQL, SQLite, and `InMemory`
- built-in recurring-job support through Kaal
- observability, governance, and standards-oriented integration surfaces for
  production operations

## Platform Map

### Core Packages

- `core/karya`: canonical runtime, CLI, execution model, operator contracts,
  workflow engine, and shared integration boundaries
- `core/karya-activerecord`: Active Record adapter surface for SQL-backed Karya
  deployments
- `core/karya-sequel`: Sequel adapter surface for SQL-backed Karya deployments

### Framework And UI Packages

- `gems/karya-dashboard`: optional dashboard addon that ships the packaged UI,
  internal API surface, and Ruby asset helpers
- `gems/karya-rails`: Rails integration paired with Active Record
- `gems/karya-hanami`: Hanami integration paired with Sequel
- `gems/karya-roda`: Roda integration paired with Sequel
- `gems/karya-sinatra`: Sinatra integration paired with Sequel

## Supported Product Surface

### First-Class Entry Points

- plain Ruby
- Rails
- Sinatra
- Roda
- Hanami
- ActiveJob compatibility

### Backend Posture

- `Postgres`: default production recommendation
- `Redis`: supported for queue-centric and low-latency deployments
- `MySQL`: supported production SQL backend
- `SQLite`: supported for constrained and embedded SQL deployments
- `InMemory`: supported for local development, examples, and tests

### Operator Surfaces

- dashboard UI for queues, workers, workflows, schedules, activity, Kaal-backed
  recurring operations, and governed actions
- operator APIs with shared filtering, pagination, and error-envelope
  conventions
- CLI and command surfaces for runtime inspection, lifecycle control, and
  automation

## Dashboard Distribution Contract

`gems/karya-dashboard` is an optional addon that framework packages can include
when a host needs the robust operator UI and the dashboard-owned internal API
surface.

When included, it publishes a packaged dashboard distribution:

- `dist/index.html`
- `dist/assets/*`
- `dist/asset-manifest.json`

Framework hosts render the shared bundle from the asset manifest instead of
forking the UI per framework. The selected framework package determines whether
the dashboard is included and which adapter path backs it: Rails pairs with
`karya-activerecord`, while Hanami, Roda, and Sinatra pair with
`karya-sequel`.

The full hosting contract, internal API positioning, asset-prefix behavior, and
mount expectations are documented in
[`docs/pages/host-workflow.md`](docs/pages/host-workflow.md).

## Local Development

Install dependencies and run the shared repository verification flow from the
repository root:

```bash
scripts/ci-install-bundles
scripts/run-all
```

For focused dashboard work:

```bash
scripts/run-dashboard-dev
```

## Documentation

The docs site under `docs/` is the authoritative source for setup, operations,
support matrices, governance guidance, migration playbooks, and troubleshooting.

Start with:

- [`docs/index.md`](docs/index.md)
- [`docs/pages/getting-started.md`](docs/pages/getting-started.md)
- [`docs/pages/frameworks/index.md`](docs/pages/frameworks/index.md)
- [`docs/pages/backends.md`](docs/pages/backends.md)
- [`docs/pages/adoption/index.md`](docs/pages/adoption/index.md)
- [`docs/pages/troubleshooting.md`](docs/pages/troubleshooting.md)
