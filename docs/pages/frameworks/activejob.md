---
title: ActiveJob
parent: Frameworks
nav_order: 6
permalink: /frameworks/activejob/
---

# ActiveJob

ActiveJob is a first-class compatibility path, especially for Rails teams
adopting Karya incrementally.

## Position

- compatibility path, not a separate framework host
- centered on the Rails and Active Record integration path
- useful for staged adoption and migration

## Use It When

- you want to adopt Karya without rewriting all job entrypoints immediately
- you need a migration path from existing Rails job infrastructure

## Common Scenarios

### Incremental Rails Adoption

Use ActiveJob as a compatibility layer while the host moves toward Karya-native
runtime and operator workflows:

```ruby
# Gemfile
gem "karya"
gem "karya-activerecord"
gem "karya-rails"
```

At this stage, teams keep the Rails-oriented entrypoint and migrate execution,
operator workflows, and reliability features in phases instead of attempting a
single cutover.

## Related Concepts

- [Rails](/frameworks/rails/): ActiveJob compatibility lives in the Rails story
- [Adoption](/adoption/): use the migration guides before planning
  cutover
