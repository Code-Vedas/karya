---
title: Plain Ruby
parent: Frameworks
nav_order: 1
---

# Plain Ruby

Plain Ruby is the most direct path into `core/karya`.

## Position

- first-class supported entrypoint
- suitable for service-style applications without a framework host
- can pair with either adapter path depending on backend choice

## Use It When

- you want direct runtime and CLI access
- you do not need a framework-native mount model
- you want the smallest host integration layer

## Common Scenarios

### Composing A Service-Style Host

Plain Ruby is the right fit when you want to assemble the runtime directly and
pick the adapter path explicitly:

```ruby
require "karya"
require "karya/activerecord" # or require "karya/sequel"

module BillingWorker
  def self.perform(*args)
    # Application work runs here.
  end
end

# Plain Ruby hosts compose the core runtime directly and choose the adapter
# path that matches the selected backend.
```

## Related Concepts

- [Backends](../backends.md): pick the backend before choosing the adapter path
- [Job Model](../runtime/job-model.md): plain Ruby uses the same runtime
  semantics as every other host
- [Observability](../observability.md): service-style hosts still need the same
  trace, log, and metric posture
