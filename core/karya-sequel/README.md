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

See [`../../docs/pages/backends.md`](../../docs/pages/backends.md) and
[`../../docs/pages/frameworks/index.md`](../../docs/pages/frameworks/index.md) for the
backend matrix and supported framework pairings.
