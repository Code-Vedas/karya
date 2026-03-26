# Karya::Rails

`karya-rails` provides the Rails host integration for Karya and composes the
core runtime with the Active Record adapter. It can also include the optional
`karya-dashboard` addon for hosts that want the robust operator UI and the
dashboard-owned internal API surface.

## Use This Package When

- you are deploying Karya inside a Rails application
- you want Rails-native mounting, session handling, and health integration
- you want to optionally mount the dashboard addon inside a Rails host
- you want the recommended Active Record pairing for the Karya framework layer

## Product Role

The Rails package represents the first-class Rails entrypoint for the platform
and participates in the documented contracts for:

- framework-native dashboard mounting when the addon is included
- operator API exposure and session-aware dashboard access
- ActiveJob compatibility and migration paths
- health, readiness, and operational integration for Rails hosts

## Recommended Pairings

- `core/karya`
- `core/karya-activerecord`
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

See the
[framework guide](https://karya.codevedas.com/frameworks/),
[dashboard hosting guide](https://karya.codevedas.com/dashboard-hosting/),
and
[adoption guide](https://karya.codevedas.com/adoption/)
for full Rails guidance.
