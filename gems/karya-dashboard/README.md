# Karya::Dashboard

`karya-dashboard` is the optional dashboard addon for Karya framework hosts. It
ships the shared operator interface, the dashboard-owned internal API surface,
and Ruby helpers for asset-manifest loading and host-page rendering.

## Use This Package When

- you want a supported framework host to expose the robust Karya operator UI
- you need the shared dashboard and internal API surface rather than building a
  framework-specific operator stack
- you are integrating dashboard workflows with runtime controls, Kaal-backed
  recurring operations, and standards-facing observability surfaces

## Product Role

This package defines the optional dashboard layer for the Karya platform:

- packaged frontend assets under `dist/`
- the internal API surface used by the dashboard-hosted operator experience
- manifest-driven script and stylesheet loading
- host rendering helpers for mount path and asset-prefix aware delivery
- one operator UI surface across Rails, Sinatra, Roda, and Hanami when the
  framework host includes the addon
- operator-facing visibility into Kaal-backed recurring scheduling

## Dependency Position

`karya-dashboard` is documented as:

- coupled to the core Karya runtime model
- added optionally by framework integrations that want the operator UI
- paired indirectly with `karya-activerecord` or `karya-sequel` through the
  framework package that includes it

In practice, Rails hosts bring it in with the Active Record path, while Hanami,
Roda, and Sinatra hosts bring it in with the Sequel path.

## Distribution Contract

The packaged dashboard contract is:

- `dist/index.html`
- `dist/assets/*`
- `dist/asset-manifest.json`

Hosts that include the addon render the manifest-driven assets and mount the
dashboard at the framework-defined path. The docs site covers hosting,
auth/session parity, internal API positioning, operator workflows, and
troubleshooting in detail.

## Development

```bash
bundle install
corepack yarn install
bin/dev
bin/build
bin/prepackage-build
bin/rspec-unit
bin/rspec-e2e
bin/rubocop
bin/reek
bin/firefox-e2e
```

See [`../../docs/pages/host-workflow.md`](../../docs/pages/host-workflow.md) and
[`../../docs/pages/operator/index.md`](../../docs/pages/operator/index.md)
for the platform-level dashboard contract.
