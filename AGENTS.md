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
- RBS must be 100% true to Ruby behavior. Mirror ownership, visibility,
  optionality, arguments, and return types. Remove stale signatures when code
  moves or disappears.
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
