# Karya::Sinatra

`karya-sinatra` provides the Sinatra host integration for Karya and composes the
core runtime with the Sequel adapter. It can also include the optional
`karya-dashboard` addon for hosts that want the robust operator UI, the
dashboard-owned internal API surface, and Kaal-facing operator workflows.

## Use This Package When

- you are integrating Karya into a Sinatra application
- you want a minimal host surface with the same Karya dashboard and operator
  model used by other frameworks
- you are using the Sequel-backed Karya integration path

## Product Role

The Sinatra package is the first-class Sinatra entrypoint for the platform and
participates in the documented contracts for:

- framework-parity dashboard mounting and asset delivery when the addon is
  included
- operator APIs, runtime controls, and session-aware dashboard use
- recurring scheduling exposure through the shared Kaal-backed model
- Sequel-backed backend integration

## Recommended Pairings

- `core/karya`
- `core/karya-sequel`
- `gems/karya-dashboard` when the host includes the optional dashboard addon
- `Postgres` as the default production backend recommendation

## Development

```bash
bundle install
bin/rspec-unit
bin/rspec-e2e
bin/rubocop
bin/reek
```

See [`../../docs/pages/frameworks/index.md`](../../docs/pages/frameworks/index.md) and
[`../../docs/pages/host-workflow.md`](../../docs/pages/host-workflow.md) for
the full Sinatra integration guidance.
