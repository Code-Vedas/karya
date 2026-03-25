# Karya

{: .note }

> Karya is in early development and is extremely unstable. Expect breaking changes and a lack of documentation until the 1.0 release.

Karya is organized as a Ruby and Node monorepo with:

- a core runtime gem
- datastore adapter gems
- framework integration gems
- a dashboard UI gem built with React, TypeScript, and Tailwind

Use the repository root scripts to install dependencies and run verification.

## Dashboard Asset Contract

The dashboard gem publishes a packaged asset contract:

- `dist/index.html`
- `dist/assets/*`
- `dist/asset-manifest.json`
