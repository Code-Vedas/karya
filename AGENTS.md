# Karya Agent Instructions

Use this file as the repo-root coding baseline.

- `core/karya` owns canonical runtime semantics. Shared behavior lands there
  first.
- Backend adapters under `core/` and framework packages under `gems/` should
  follow `core/karya` vocabulary and contracts.
- Keep public API small. Internal helpers, support modules, and constants
  should stay private unless they are intentional extension points.
- Prefer composition over inheritance.
- Split large files by responsibility, not arbitrary size. Avoid generic
  `utils` or `helpers` dumping grounds.
- Keep validation, normalization, and state transitions explicit.
- Trace concrete state changes for time, retries, leases, shutdown, and shared
  state. Watch for TOCTOU gaps.
- Do not symbolize, intern, or cache unbounded input.
- `docs/` is future-state product documentation with no exceptions. Review and
  edit it as completed product documentation, not as a mirror of what is
  implemented today. For `docs/`, fix contradictions, stale names, broken
  links, impossible workflows, and inconsistent support boundaries, but do not
  downgrade product behavior merely because code is not there yet.
- RBS must be 100% true to Ruby behavior. Mirror ownership, visibility,
  optionality, arguments, and return types. Remove stale signatures when code
  moves or disappears.
- RBS is whole-implementation for `core/karya`: shared internal helpers live
  under `Karya::Internal`, with Ruby files in `lib/karya/internal/**` and
  signatures in `sig/karya/internal/**`. These constants are visible for
  implementation wiring but unsupported as public API.
- Owner-local internals stay nested under their owning class/module and may be
  typed inside that owner RBS file rather than as one RBS file per Ruby file.
- For `core/karya` work, normally run:

```bash
cd core/karya
bin/reek
bin/rubocop
bin/rspec-unit
```

- Review-specific guidance lives in
  `.github/instructions/review.instructions.md`.
- Path-specific instruction files under `.github/instructions/` should carry
  the detailed rules. Prefer repo files over client-specific config; use client
  config only when a tool is known not to load repository instruction files
  reliably.
