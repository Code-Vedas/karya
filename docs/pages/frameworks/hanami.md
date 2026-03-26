---
title: Hanami
parent: Frameworks
nav_order: 5
---

# Hanami

Hanami is a first-class Karya host with the Sequel integration path.

## Position

- first-class supported framework
- pairs with `karya-sequel`
- can optionally include `karya-dashboard`

## Integration Shape

- Hanami-native mounting behavior
- shared operator surface when the dashboard addon is included
- Kaal-backed scheduling exposure aligned with the platform model

## Common Scenarios

### Hanami Host With Shared Operator Surface

Hanami hosts keep the dashboard under the framework’s own mount model:

```ruby
# config/routes.rb
slice :dashboard, at: Karya::Hanami.mount_path
```

```ruby
require "hanami"
require "karya/hanami"

KaryaHost = proc do |env|
  if env["PATH_INFO"] == "/karya"
    [200, { "content-type" => "text/html; charset=utf-8" }, [
      Karya::Hanami.render_dashboard_page(prefix: "admin")
    ]]
  else
    [404, { "content-type" => "text/plain" }, ["not found"]]
  end
end
```

This illustrates both the route-level mount story and the shared dashboard
rendering model.

## Related Concepts

- [Dashboard Hosting](../host-workflow.md): Hanami still follows the shared
  distribution contract
- [Backends](../backends.md): Hanami usually pairs with the Sequel path
