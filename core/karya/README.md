# Karya

Core runtime and CLI foundation for Karya.

`Karya` is the base gem for the Karya monorepo. It owns the shared runtime,
backend, plugin, tooling, and CLI surfaces that adapter and framework
integration gems build on.

## Development

```bash
bundle install
bin/rspec-unit
bin/rspec-e2e
bin/rubocop
bin/reek
bundle exec exe/karya --version
```
