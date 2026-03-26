---
title: Dashboard Hosting
nav_order: 9
permalink: /dashboard-hosting/
---

# Dashboard Hosting

`gems/karya-dashboard` is an optional addon for framework hosts. When a
framework includes it, the host mounts one shared dashboard distribution instead
of maintaining a framework-specific UI fork.

That keeps the operator experience consistent across frameworks while still
letting each host own its own routing, auth/session behavior, and integration
details.

## Packaged Distribution Contract

The authoritative dashboard package contract is:

- `dist/index.html`
- `dist/assets/*`
- `dist/asset-manifest.json`

The asset manifest is the source of truth for the scripts, stylesheets, and
mount metadata required by the dashboard renderer.

## What The Addon Ships

When included by a framework host, `karya-dashboard` ships:

- the packaged operator UI
- the dashboard-owned internal API surface used by that UI
- Kaal-facing operator workflows for recurring jobs and schedules
- Ruby helpers for manifest loading and host-page rendering

## Build And Packaging Flow

From `gems/karya-dashboard`:

```bash
bin/build
bin/prepackage-build
```

`prepackage-build` verifies the packaged distribution and writes the manifest
used by the host-side rendering helpers.

## Example Host Patterns

These examples make the hosting shape clear without turning this page into a
framework-by-framework contract reference.

### Rails Mount

```ruby
# config/routes.rb
mount Karya::Rails::Engine => "/karya"
```

### Sinatra Mount

```ruby
get "/karya" do
  content_type "text/html"
  Karya::Sinatra.render_dashboard_page(scope: "ops")
end
```

### Roda Mount

```ruby
r.is "karya" do
  response["content-type"] = "text/html; charset=utf-8"
  Karya::Roda.render_dashboard_page(scope: "internal")
end
```

### Hanami Mount

```ruby
slice :dashboard, at: Karya::Hanami.mount_path
```

## Host Responsibilities

Every host that includes the addon is responsible for:

- serving the packaged asset files under a stable asset path
- rendering the dashboard document with the manifest-driven asset tags
- setting the dashboard mount path that the frontend uses for operator routing
- aligning auth and session behavior with the framework’s operator access model
- exposing the internal dashboard APIs that the UI depends on

## Mount Path And Asset Prefix

The dashboard renderer supports:

- `mount_path`: the URL base that the dashboard treats as its mounted home
- `asset_prefix`: the prefix used when assets are served behind a subpath or
  CDN-backed location

The asset-prefix contract normalizes host-provided prefixes so the resulting
asset URLs remain stable across local paths, subpaths, and fully qualified CDN
prefixes.

## Example Asset Prefix Usage

Hosts use `asset_prefix` when the packaged assets are served from a subpath or a
separate asset origin:

```ruby
Karya::Dashboard.render_document(
  mount_path: "/karya",
  asset_prefix: "/dashboard-assets"
)
```

CDN-backed paths follow the same model:

```ruby
Karya::Dashboard.render_document(
  mount_path: "/karya",
  asset_prefix: "https://cdn.example.com/karya"
)
```

Use these examples to understand the hosting model. The framework pages remain
the place to describe host-specific mounting and auth/session behavior.

## Dependency And Pairing Model

`karya-dashboard` is positioned as:

- coupled to the shared Karya runtime model
- added optionally by framework packages
- paired with `karya-activerecord` or `karya-sequel` through the framework that
  includes it

Rails uses the Active Record path. Hanami, Roda, and Sinatra use the Sequel
path.

## Framework Examples

- Rails mounts the dashboard through the Rails engine path, typically under
  `/karya`
- Sinatra and Roda expose the dashboard from framework routes that return the
  rendered HTML document
- Hanami uses the Hanami mount path contract and shared rendering model

## Troubleshooting Signals

Common hosting failures include:

- missing `dist/asset-manifest.json`
- stale packaged assets after frontend changes
- incorrect asset prefix leading to broken stylesheet or module loading
- mismatch between the configured mount path and the served route

See [Troubleshooting](/troubleshooting/) for recovery steps.
