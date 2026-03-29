# Karya

`karya` is the canonical runtime and CLI package for the Karya platform.

It defines the shared job, queue, worker, workflow, operator, and integration
contracts that the backend adapters, framework packages, dashboard, and
governance features build on.

## Use This Package When

- you are integrating Karya into a plain Ruby application
- you need the shared CLI, runtime lifecycle, or operator command surfaces
- you are building on the core execution, reliability, or workflow contracts
- you need the source of truth for platform-level terminology and behavior

## Product Role

The core package owns the platform-wide behavior for:

- job and queue lifecycle
- worker bootstrap, graceful drain, and runtime supervision
- routing, retries, deadlines, uniqueness, dead-letter handling, and recovery
- workflow composition, replay, compensation, checkpoints, and evolution
- operator-facing control and inspection boundaries
- shared plugin, configuration, and backend selection contracts

## Pairings

- plain Ruby hosts consume `karya` directly
- framework packages compose `karya` with the appropriate adapter and dashboard
  package
- backend integrations rely on the contracts defined here for parity and
  capability reporting

## Development

```bash
bundle install
bin/rspec-unit
bin/rspec-e2e
bin/rubocop
bin/reek
bundle exec exe/karya --version
```

## Worker Bootstrap

The core package now includes a single-process worker runtime. Workers subscribe
to queues, reserve jobs, resolve handlers from an explicit registry keyed by
`job.handler`, and persist `succeeded` or `failed` outcomes through the queue
store execution flow.

The CLI exposes a minimal bootstrap command:

```bash
bundle exec exe/karya worker billing --worker-id worker-1 --handler billing_sync=BillingJob
```

For platform-level setup, workflows, and operator guidance, use the
[Karya documentation](https://karya.codevedas.com/).
