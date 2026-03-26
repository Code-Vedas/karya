# Karya::Roda

`karya-roda` provides the Roda host integration for Karya and composes the core
runtime with the Sequel adapter. It can also include the optional
`karya-dashboard` addon for hosts that want the robust operator UI, the
dashboard-owned internal API surface, and Kaal-facing operator workflows.

## Use This Package When

- you are embedding Karya in a Roda application
- you want a lightweight Rack-oriented host with the shared Karya operator
  surface
- you prefer the Sequel integration path for backend-backed deployments

## Product Role

The Roda package is the first-class Roda entrypoint for the platform and aligns
Roda with the documented contracts for:

- framework-native dashboard delivery without UI forks when the addon is
  included
- operator controls, inspection, and dashboard access
- recurring scheduling and runtime supervision surfaces
- Sequel-backed persistence and backend capability parity

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

See [`../../docs/pages/frameworks/index.md`](../../docs/pages/frameworks/index.md),
[`../../docs/pages/operator/index.md`](../../docs/pages/operator/index.md), and
[`../../docs/pages/host-workflow.md`](../../docs/pages/host-workflow.md)
for the full Roda operator and hosting guidance.
