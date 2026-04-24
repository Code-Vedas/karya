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
- Owner-local `Internal` namespaces stay nested under their owning
  class/module and should be typed explicitly.
- When an owner-local `Internal` namespace spans multiple Ruby files, prefer
  dedicated RBS files mirroring that owner-local file layout instead of
  collapsing the whole namespace into one large owner file.
- Owner-local nested helpers that are not under an `Internal` namespace may be
  omitted from RBS unless they are needed for correctness, visibility, or
  typechecking clarity.
- If Ruby is split into responsibility-named owner-local files, prefer an RBS
  layout that keeps those ownership boundaries obvious instead of hiding the
  split behind catch-all signatures.
- Match actual ownership. If a method moves to a support module, move the
  signature to that support module.
- Match actual visibility. Private/internal structure in Ruby should not appear
  as accidental public API in RBS.
- Private constants may be typed when they help keep the runtime implementation
  honest, but they must stay in a `private` section and must not appear as
  supported public API.
- If a private constant is not useful to model directly, omit the constant and
  type the private methods that use it instead.
- When Ruby moves helper readers, support classes, or support methods under
  `private`, mirror that visibility change in the same RBS patch.
- Match argument names, keyword names, optionality, return types, and nested
  module/class structure.
- Remove stale entries for deleted methods, constants, and modules.
- Do not use `untyped`, `any`, or other generic escape hatches where a concrete
  type is knowable.
- Do not widen types to hide Ruby/RBS drift.
- When changing `core/karya/lib/karya/...`, check the mirrored file under
  `core/karya/sig/karya/...` in the same change.
