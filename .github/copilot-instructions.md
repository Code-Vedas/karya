# Karya Copilot Instructions

For implementation work in this repository, follow these rules first. Use
`.github/instructions/review.instructions.md` as supplemental review guidance,
not as the primary coding file.

Detailed rules live in path-specific files under `.github/instructions/`.
Prefer repository instruction files over client-specific config. Use client
config only when a tool is known not to load repository instruction files
reliably.

## Placement

- `core/karya` owns canonical runtime semantics.
- Backend adapters in `core/karya-activerecord` and `core/karya-sequel` should
  adopt shared contracts, not invent them.
- Framework and dashboard packages under `gems/` should stay vocabulary-aligned
  with `core/karya`.
- Put signatures in the mirrored `sig/` path for every changed Ruby surface.

## Structure

- Prefer composition over inheritance.
- Split large files by responsibility, not by arbitrary size.
- Avoid `utils` or `helpers` dumping grounds.
- Keep internal helpers private and minimize accidental public API.
- Keep CLI parsing separate from runtime policy.

## Implementation

- Trace concrete state changes for time, retries, leases, shutdown, and shared
  state.
- Validate raw input before normalization when order matters.
- Keep types consistent from input to validation to runtime use.
- Do not symbolize or cache unbounded input.
- Use actionable, Karya-specific error messages.

## RBS

- RBS must be 100% true to the Ruby implementation.
- Mirror ownership, visibility, optionality, argument names, and return types.
- Move or delete signatures when methods move or disappear.
- Do not widen types to hide drift.

## Verification

For `core/karya` changes, run:

```bash
cd core/karya
bin/reek
bin/rubocop
bin/rspec-unit
```
