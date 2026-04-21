---
applyTo: "core/karya/lib/karya/**/*.rb,core/karya/spec/**/*.rb"
---

# Core Karya Coding Instructions

These rules apply to changes in the canonical runtime package.

## Ownership

- `core/karya` is the source of truth for shared runtime semantics.
- New job, queue, worker, lifecycle, retry, timeout, expiration, CLI, and
  operator contracts belong here first.
- Do not push canonical behavior into adapter packages or framework packages.

## File Placement

- Queue store behavior goes under `lib/karya/queue_store/...`.
- Worker runtime behavior goes under `lib/karya/worker/...`.
- Supervisor and process management go under `lib/karya/worker_supervisor/...`.
- CLI parsing and option coercion go under `lib/karya/cli/...`.
- Tests belong under mirrored paths in `spec/`.

## Structure

- Prefer small, responsibility-named support modules or classes over one large
  orchestration file.
- When a class grows mixed responsibilities, extract by behavior boundary.
  Example: `execution_support`, `expiration_support`, `request_support`,
  `recovery_support`.
- Do not create generic dumping grounds named `utils`, `helpers`, or similar.
- Keep internal support code private with consistent visibility scoping.

## Runtime Rules

- Validate raw input before normalization when order matters.
- Keep input type flow consistent from interface to validation to internal use.
- Trace line-by-line where time, signals, leases, retries, or shared state can
  change between check and action.
- Error handling must not hide fatal problems or create retry loops.
- Blocking operations need explicit timeout or cancellation posture.
- Avoid global mutable state.
- Do not symbolize or cache unbounded input.
- Do not add inline Reek suppressions such as `# :reek:` comments. Address the
  smell in code first; if an exclusion is unavoidable, keep it narrow in
  `core/karya/.reek.yml`.

## Change Bar

- Add focused tests for new branches and state transitions.
- Update docs only when behavior, naming, or supported usage changed.
- Check sibling packages for contract drift when shared behavior changes.
- Run:

```bash
cd core/karya
bin/reek
bin/rubocop
bin/rspec-unit
```
