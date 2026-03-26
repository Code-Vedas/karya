# Karya::Dashboard

Packaged dashboard frontend for Karya.

`karya-dashboard` ships the React, TypeScript, SCSS, and Vite-built dashboard
bundle together with a Ruby wrapper that exposes the packaged asset manifest
and HTML rendering helpers for the dashboard itself.

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
