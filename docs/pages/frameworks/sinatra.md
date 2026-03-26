---
title: Sinatra
parent: Frameworks
nav_order: 3
---

# Sinatra

Sinatra is a first-class lightweight host for Karya.

## Position

- first-class supported framework
- pairs with `karya-sequel`
- can optionally include `karya-dashboard`

## Integration Shape

- minimal host surface
- shared operator model with other frameworks
- Kaal-backed scheduling story consistent with the broader platform

## Common Scenarios

### Minimal Host With Operator UI

Sinatra hosts stay minimal while still being able to mount the optional
dashboard addon:

```ruby
require "sinatra/base"
require "karya/sinatra"

class KaryaHost < Sinatra::Base
  get "/karya" do
    content_type "text/html"
    Karya::Sinatra.render_dashboard_page(scope: "ops")
  end
end
```

This shape reflects the current dummy-host pattern in the repository: Sinatra
owns the route and Karya renders the shared dashboard document.

## Related Concepts

- [Dashboard Hosting](../host-workflow.md): host responsibilities stay the same
  even in a minimal app
- [Backends](../backends.md): Sinatra usually pairs with the Sequel path
