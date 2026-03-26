# Host Workflow

Karya ships the operator UI through `gems/karya-dashboard`.

## Packaged Asset Contract

Run the dashboard packaging flow from `gems/karya-dashboard`:

```bash
bin/build
bin/prepackage-build
```

The packaged output is:

- `dist/index.html`
- `dist/assets/*`
- `dist/asset-manifest.json`
