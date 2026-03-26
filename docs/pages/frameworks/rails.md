---
title: Rails
parent: Frameworks
nav_order: 2
permalink: /frameworks/rails/
---

# Rails

Rails is a first-class Karya host and the natural Active Record pairing.

## Position

- first-class supported framework
- recommended path for Rails-native adoption
- primary compatibility path for ActiveJob

## Integration Shape

- pairs with `karya-activerecord`
- can optionally include `karya-dashboard`
- exposes framework-native mounting, session behavior, and health integration

## Common Scenarios

### Rails Host With Dashboard

Rails is the most natural path when the host wants Active Record plus the
optional dashboard addon:

```ruby
# Gemfile
gem "karya"
gem "karya-activerecord"
gem "karya-rails"
gem "karya-dashboard"
```

```ruby
# config/routes.rb
mount Karya::Rails::Engine => "/karya"
```

This is the natural shape for Rails-native mounting, the ActiveJob
compatibility path, and the robust operator UI in the same host.

## Related Concepts

- [ActiveJob](activejob.md): Rails is the main compatibility path
- [Dashboard Hosting](../host-workflow.md): mount and asset delivery details
  live there
- [Backends](../backends.md): Rails usually pairs with the Active Record path
