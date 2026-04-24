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
- For request-derived runtime state, define semantic scope, collision posture,
  and bounded growth explicitly in the same change.
- Do not symbolize, intern, or cache unbounded input.
- Do not add inline Reek suppressions such as `# :reek:` comments. Address the
  smell in code first; if an exclusion is unavoidable, keep it narrow in the
  package `.reek.yml`.
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
- Owner-local `Internal` namespaces stay nested under their owning
  class/module and should be typed explicitly. Prefer dedicated owner-local RBS
  files that mirror the Ruby file layout when the namespace spans multiple
  files.
- Owner-local nested helpers that are not under an `Internal` namespace do not
  need explicit RBS by default. Type them only when they are needed for
  correctness, visibility, or typechecking clarity.
- Owner-local `Internal` Ruby files should prefer mirrored unit specs under
  `spec/.../internal/**`.
- Responsibility-split owner-local Ruby files outside `Internal` should also
  prefer mirrored unit specs under their owner path when they own direct
  behavior.
- Large owner integration specs such as `in_memory_*` should cover public API
  behavior only. Do not use owner-private setup or assertions there via
  `instance_variable_get`, direct internal constant reach-in, or private state
  helpers that inspect implementation storage.
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
