# Karya::ActiveRecord

`karya-activerecord` provides the Active Record adapter surface for Karya SQL
deployments.

## Use This Package When

- your host application uses Rails or another Active Record-based environment
- you want SQL-backed Karya behavior through the Active Record stack
- you need the adapter layer that aligns framework integration with the broader
  backend capability matrix

## Product Role

This package bridges the Karya runtime to Active Record-backed persistence and
backend wiring. It participates in the supported platform contracts for:

- backend selection and capability reporting
- durable `Karya::QueueStore::Base` enqueue, lease, execution, and recovery
  semantics when SQL-backed queue stores are implemented
- persistence for jobs, workflows, schedules, audit-relevant state, and operator
  inspection data
- parity with the shared runtime and operator model

## Recommended Pairings

- `gems/karya-rails` for Rails hosts
- `Postgres` as the default production backend recommendation
- `MySQL` and `SQLite` where their documented support tradeoffs fit the
  deployment

## Development

```bash
bundle install
bin/rspec-unit
bin/rspec-e2e
bin/rubocop
bin/reek
```

See the
[Karya backend matrix](https://karya.codevedas.com/backends/)
and
[Rails integration guidance](https://karya.codevedas.com/frameworks/).
