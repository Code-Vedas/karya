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

The core package now includes a supervisor-managed worker runtime. The
`karya worker` CLI starts a master process that forks child workers, subscribes
them to queues, resolves handlers from an explicit registry keyed by
`job.handler`, and persists `succeeded` or `failed` outcomes through the queue
store execution flow.

The CLI accepts separate `--processes` and `--threads` settings. The supervisor
manages child worker processes, and each child process always runs work through
a thread pool, even when `--threads 1` is used. The supervisor owns `SIGINT`
and `SIGTERM` handling: the first signal begins coordinated drain across child
workers, while a repeated signal escalates to forced termination. Worker
threads stop polling, let running jobs finish when possible, and release
reservations that were acquired but not yet started.

The CLI exposes a minimal bootstrap command:

```ruby
# config/worker_boot.rb
require 'karya'

Karya.configure_queue_store(Karya::QueueStore::InMemory.new)

class BillingJob
  def self.call(**)
  end
end
```

```bash
bundle exec ruby -r./config/worker_boot -Ilib exe/karya worker billing \
  --processes 1 \
  --threads 1 \
  --state-file /tmp/karya-runtime-billing.json \
  --env-prefix billing_worker \
  --worker-id worker-1 \
  --handler billing_sync=BillingJob
```

Per-worker env overrides use the explicit env prefix:

```bash
KARYA_BILLING_WORKER_PROCESSES=2
KARYA_BILLING_WORKER_THREADS=4
```

Use multiple processes or threads only with a queue store backed by shared
process-safe storage and thread-safe handlers. `Karya::QueueStore::InMemory` is
suitable for local examples and bootstrapping only.

`Karya.configure_logger` and `Karya.configure_instrumenter` set process-wide
defaults. When multiple runtimes share the same process, pass explicit
`logger:` and `instrumenter:` collaborators to keep runtime boundaries isolated.

## Runtime Inspection And Control

`Karya::WorkerSupervisor` now exposes a minimal supported inspection and control
surface:

- `runtime_snapshot` for supervisor, child-process, and worker-thread topology
- `begin_drain` for graceful shutdown
- `force_stop` for forced shutdown

The CLI exposes the same local-runtime surface through the state file written by
`karya worker` for inspection plus a supervisor-owned local Unix control socket
for drain and force-stop requests:

```bash
bundle exec exe/karya runtime inspect --state-file /tmp/karya-runtime-billing.json
bundle exec exe/karya runtime drain --state-file /tmp/karya-runtime-billing.json
bundle exec exe/karya runtime force-stop --state-file /tmp/karya-runtime-billing.json
```

This issue intentionally stops at supervisor-wide control and coarse runtime
state. Dashboard-owned APIs, remote transports, and fine-grained operator
actions remain separate work.

For platform-level setup, workflows, and operator guidance, use the
[Karya documentation](https://karya.codevedas.com/).
