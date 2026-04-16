# Karya::Sequel

`karya-sequel` provides the Sequel adapter surface for Karya SQL deployments.

## Use This Package When

- your host stack is built around Sequel
- you are integrating Karya with Hanami, Roda, or Sinatra
- you want SQL-backed persistence through the Sequel-oriented Karya path

## Product Role

This package binds the shared Karya runtime contracts to Sequel-backed
deployments and supports the platform documentation for:

- backend capability and parity expectations
- durable `Karya::QueueStore::Base` enqueue, lease, execution, and recovery
  semantics when SQL-backed queue stores are implemented
- persistence for execution, workflow, schedule, and audit-oriented state
- framework-native integration for Sequel-based hosts

## Recommended Pairings

- `gems/karya-hanami`
- `gems/karya-roda`
- `gems/karya-sinatra`
- `Postgres` as the default production backend recommendation
- `MySQL` and `SQLite` for supported alternative SQL deployments

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
[framework integration guidance](https://karya.codevedas.com/frameworks/)
for supported pairings.
