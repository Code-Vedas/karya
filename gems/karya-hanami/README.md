# Karya::Hanami

`karya-hanami` provides the Hanami host integration for Karya and composes the
core runtime with the Sequel adapter. It can also include the optional
`karya-dashboard` addon for hosts that want the robust operator UI, the
dashboard-owned internal API surface, and Kaal-facing operator workflows.

## Use This Package When

- you are running Karya in a Hanami application
- you want Hanami-native dashboard mounting and Sequel-backed persistence
- you need the same operator and scheduling model used across supported hosts

## Product Role

The Hanami package is the first-class Hanami entrypoint for the platform and
aligns Hanami with the documented contracts for:

- framework parity across dashboard mounting and asset delivery when the addon
  is included
- operator-facing APIs and dashboard workflows
- Kaal-backed recurring scheduling exposure
- Sequel-backed persistence and backend capability reporting

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

See the
[framework guide](https://karya.codevedas.com/frameworks/)
and
[dashboard hosting guide](https://karya.codevedas.com/dashboard-hosting/)
for the full Hanami integration story.
