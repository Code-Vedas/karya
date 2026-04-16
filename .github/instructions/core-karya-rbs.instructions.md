---
applyTo: "core/karya/sig/**/*.rbs"
---

# Core Karya RBS Instructions

RBS in this repository is a correctness contract.

- RBS must be 100% true to the Ruby implementation it mirrors.
- `core/karya` uses whole-implementation RBS: internal implementation helpers
  should be typed when they help keep runtime code honest.
- Shared internal helpers belong under `lib/karya/internal/**` and
  `sig/karya/internal/**`, inside `Karya::Internal`.
- `Karya::Internal` constants are visible for implementation wiring but are
  unsupported public API.
- Owner-local internals stay nested under their owning class/module and can be
  typed inside the owner RBS file.
- Match actual ownership. If a method moves to a support module, move the
  signature to that support module.
- Match actual visibility. Private/internal structure in Ruby should not appear
  as accidental public API in RBS.
- Match argument names, keyword names, optionality, return types, and nested
  module/class structure.
- Remove stale entries for deleted methods, constants, and modules.
- Do not use `untyped`, `any`, or other generic escape hatches where a concrete
  type is knowable.
- Do not widen types to hide Ruby/RBS drift.
- When changing `core/karya/lib/karya/...`, check the mirrored file under
  `core/karya/sig/karya/...` in the same change.
