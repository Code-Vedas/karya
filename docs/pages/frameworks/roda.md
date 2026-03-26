---
title: Roda
parent: Frameworks
nav_order: 4
permalink: /frameworks/roda/
---

# Roda

Roda is a first-class Rack-oriented host for Karya.

## Position

- first-class supported framework
- pairs with `karya-sequel`
- can optionally include `karya-dashboard`

## Integration Shape

- Roda-native routing for the operator surface
- shared packaged dashboard model when the addon is included
- same operator and scheduling vocabulary as other hosts

## Common Scenarios

### Rack-Oriented Host With Shared UI

Roda hosts expose the dashboard through a native route:

```ruby
require "roda"
require "karya/roda"

class KaryaHost < Roda
  route do |r|
    r.is "karya" do
      response["content-type"] = "text/html; charset=utf-8"
      Karya::Roda.render_dashboard_page(scope: "internal")
    end
  end
end
```

This keeps the host thin while reusing the same dashboard addon and operator
model used by the other frameworks.

## Related Concepts

- [Dashboard Hosting](../host-workflow.md): shared asset delivery still applies
- [Search And Drilldowns](../operator/search-drilldowns.md): Roda hosts expose
  the same operator flows as other frameworks
