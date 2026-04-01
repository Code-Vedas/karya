# PR Review Instructions

Use these instructions when reviewing pull requests in this repository. Favor
high-signal semantic review over generic style feedback.

## Future-State Docs

- Treat `README.md` files and everything under `docs/` as future-state product
  documentation.
- Do not flag a PR just because the documentation describes product capability
  that is not yet fully present in code.
- Do flag contradictions, stale names, broken links, impossible workflows, or
  claims that conflict with explicit repository structure and documented support
  boundaries.

## Repo-Specific Review Supplement

- This repository is a monorepo. When changes touch shared contracts, check for
  drift across sibling packages under `core/`, adapters, and framework
  integrations.
- When reviewing runtime, queue-store, or lifecycle changes in `core/karya`,
  cross-check any impacted README/docs examples and package-level scripts.
- When reviewing dashboard, framework integration, or backend-facing changes,
  verify the owning package still reflects the same public surface and naming as
  `core/karya`.

## Required Review Checks

- Run secret scan checks.
- Run performance and security review checks.
- Run semantic and logic-error review checks.
- Run spelling and grammar checks.
- Do not spend review effort on automated linter feedback since those tools run
  in CI. Do review code clarity, logic simplification, error message quality,
  and test coverage completeness.
- **Trace concretely, don't reason abstractly:** For each code path, identify
  the exact line numbers where state can change, where execution can block, or
  where types are coerced. Abstract reasoning like "this seems safe" is
  insufficient.

## Concrete Trace Analysis Rules

These rules require tracing actual execution paths, not abstract reasoning.

### Time-of-Check-to-Time-of-Use (TOCTOU) Races

For any code that checks state then acts on it:

- Identify ALL external state: signals, time, shared memory, process state
- Trace: Can state change BETWEEN the check and the action?
- Look for patterns like:

  ```ruby
  return if shutdown?  # Check
  do_work()            # ← Signal can arrive HERE
  ```

- **Required:** Find the exact line numbers where state can change

### Control Flow Reachability

For any cleanup/escalation/fallback code:

- Trace: Can execution ACTUALLY reach this code?
- Look for blocking operations that prevent fallthrough:

  ```ruby
  send_signal("TERM")
  blocking_wait()      # ← Hangs forever if TERM fails
  send_signal("KILL")  # Never reached!
  ```

- **Required:** Verify all code paths are reachable under failure conditions

### Error Handling Side Effects

For any error-handling or retry block:

- Don't just check "are errors handled?"
- Trace: Does the error handling CREATE new problems?
- Look for:
  - Infinite retry loops
  - Signal suppression (catching interrupts)
  - Converting fatal errors to warnings
  - Swallowing exceptions that should propagate
- **Required:** Verify error handling doesn't make the system unstoppable or
  hide bugs

### Input Type Flow Tracing

For any user input (CLI, API, config):

- Trace the EXACT type from input → validation → internal use
- Check EVERY layer:
  1. What type does the interface accept? (string, numeric, boolean)
  2. What type does validation expect?
  3. What type does internal code require?
- Look for mismatches where accepted types do not match validated or consumed
  types
- **Required:** Document type at each layer, flag any coercion gaps

### Validation Order vs Normalization

For any input validation:

- Identify WHERE validation happens vs WHERE normalization happens
- **Critical rule:** Validation MUST happen on raw input, not normalized output
- Look for:

  ```ruby
  value = input || default  # Normalization FIRST
  validate(value)           # Validates default, not input! ⚠️
  ```

- Correct pattern:

  ```ruby
  validate(input)           # Validate FIRST
  value = input || default  # Normalize AFTER
  ```

- **Required:** Verify validation sees actual input, not preprocessed/normalized
  values

### Documentation Reality Gaps

For any code examples in README/docs:

- Don't just check "is code correct?"
- **Run the example mentally:** Does it actually work?
- Check:
  - Are prerequisites documented? (database setup, config files)
  - Do option combinations work?
  - Are types correct?
  - Do code snippets match actual APIs?
- **Required:** Flag any example that would fail if run as shown

### API Surface Consistency

For any public constants/methods:

- Don't just check "are NEW things marked private?"
- Scan ALL constants/methods in the file
- Check: Is visibility CONSISTENT across the file?
- Look for pattern violations where some internal constants are marked private
  but others with similar scope are left public
- **Required:** Verify ALL implementation details are consistently scoped

## Architecture Guidelines Review

These checks enforce architecture guidelines. Apply them to every code change.

### Design Principles

- **Composition over inheritance:** Flag deep inheritance hierarchies. Prefer
  modules/mixins and collaborator injection over long class chains.
- **Single Responsibility Principle:** Flag classes that mix responsibilities
  (logic + IO + orchestration). Each class should own one clear job.
- **Dependency injection:** Flag code that reaches for globals or class-level
  state when a collaborator could be passed in. Look for singleton access in
  non-entrypoint code.
- **Explicit control flow:** Flag hidden execution paths, excessive
  meta-programming, or dynamic dispatch that obscures behavior. Prefer explicit
  code over clever abstractions.

### Public/Internal Boundary

- **Namespace policy:** Verify that internal support classes are not accidentally
  exposed as public API. Check for consistent visibility scoping.
- **Minimal public surface:** Flag new public methods or classes that could be
  internal. Only entrypoints, error classes, and documented extension points
  should be public.
- **No leaking internals:** Flag cases where internal normalizers, validators,
  or support objects are reachable from outside their owning module without
  explicit intent.

### Configuration and Boot Policy

- **Explicit configuration:** Flag implicit environment dependencies in
  non-CLI code. Configuration should flow through explicit objects, not ambient
  state.
- **Fail-fast validation:** Flag code that allows partially invalid
  configuration to proceed. Validate early, fail with actionable errors.
- **Separation of parsing and policy:** Flag CLI or controller code that mixes
  input parsing with runtime configuration assembly. These are separate
  responsibilities.

### Concurrency and State

- **Thread-safety by default:** Flag shared mutable state without
  synchronization. Assume multi-threaded execution.
- **No global mutable state:** Flag module-level or class-level mutable state
  unless explicitly documented with concurrency guarantees.
- **Explicit resource management:** Flag code that opens resources (threads,
  connections, files) without clear cleanup paths.
- **Timeouts on blocking operations:** Flag indefinite blocking without timeout
  or cancellation mechanisms.
- **Documented concurrency contract:** Flag runtime components that use
  processes, threads, or shared state without documenting safety guarantees.

### Extensibility and Strategy

- **Duck-typed extension points:** Flag extension mechanisms that require
  inheritance. Prefer duck typing and registration.
- **Strategy pattern consistency:** When pluggable behavior exists, verify all
  implementations satisfy the same contract.
- **No hardcoded behavior:** Flag behavior that should be replaceable but is
  baked into a specific implementation.

### Observability

- **Pluggable logger interface:** Flag hardcoded logging output or
  framework-coupled logging. Logger should be injectable.
- **Instrumentation hooks:** Flag significant runtime events that lack
  instrumentation surface.
- **Structured, minimal logging:** Flag noisy or unstructured log output.

### Error Handling

- **Namespaced errors:** Flag generic error raises. Use project-specific error
  hierarchies.
- **Actionable messages:** Flag error messages that do not help the developer
  diagnose and fix the problem.
- **No silent swallowing:** Flag bare rescue/catch without re-raise or explicit
  handling. Flag nil/null returns for error conditions.
- **Fail fast:** Flag code that continues in an invalid state instead of
  raising.

### Load-Time Behavior

- **Side-effect-free requires/imports:** Flag code that starts threads, opens
  connections, or mutates global state during module loading.
- **Explicit initialization:** Runtime startup should happen through explicit
  entrypoints, not as a side effect of loading.

### DRY and Maintainability

- **Abstract only after real duplication:** Flag premature abstractions or
  indirection without demonstrated need. Two similar-looking blocks are not
  duplication if they serve different responsibilities.
- **Readability over cleverness:** Flag clever metaprogramming, DSL-building,
  or abstraction that sacrifices readability.
- **No dumping grounds:** Flag `utils/`, `helpers/`, or similarly named modules
  that collect unrelated behavior.

### Performance and Resources

- **Explicit resource usage:** Flag hidden expensive operations (thread
  creation, large allocations) behind simple-looking method calls.
- **Clean resource release:** Flag resources that lack cleanup paths (threads,
  sockets, file handles).
- **No unnecessary allocations:** Flag allocation-heavy patterns in hot paths
  (e.g., interning unbounded user input, repeated object creation in loops).

## Review Priorities

- Check internal consistency across `README.md` files and `docs/`.
- Check that documentation across different packages or components agrees.
- Check that optional versus first-class behavior is described clearly.
- Check for contradictions, unsupported assumptions, broken references, and weak
  review reasoning.
- **Execution trace verification:** For shutdown, cleanup, and error paths,
  trace line-by-line to verify code is reachable under failure conditions.
- **State mutation points:** Identify every line where external state (signals,
  time, concurrency) can change, and verify checks are still valid at action.
- **Type consistency end-to-end:** Trace types from user input through all
  layers to final use, flag any implicit coercion or mismatch.
- **Architecture alignment:** Verify changes follow composition over
  inheritance, dependency injection, explicit control flow, and public/internal
  boundary rules.

## Code Review Rules

- Treat changes under library source directories as package contract work unless
  the code is clearly marked private or internal.
- Treat changes in adapter or integration packages as cross-package contract
  work. Review for drift against the canonical runtime vocabulary and public
  guidance in docs and package READMEs.
- Flag accidental API expansion. In particular:
  - helper methods exposed as public unintentionally
  - helper constants or modules that become externally visible without intent
  - value-object helpers that leak internal normalization entrypoints
- Flag memory-risk patterns. In particular:
  - interning or symbolizing arbitrary user or application input
  - caches or registries that can grow from unbounded input
  - lookup paths that autovivify persistent containers on read
- Flag invariant gaps in returned runtime structures. In particular:
  - state maps that are not total over registered states
  - extension APIs that register states but leave derived views inconsistent
  - state-transition helpers that bypass validation or return partial views
- Flag cross-package compatibility gaps. In particular:
  - vocabulary drifting between core packages, integration layers, and docs
  - adapter packages assuming behavior not guaranteed by the core
  - entrypoints exposing behavior inconsistent with package README guidance
- Prefer comments about behavior, API visibility, invariants, and memory
  characteristics over comments about formatting.

## Docs And Example Review Rules

- Verify local documentation links and navigation.
- Verify code snippets match the repository's supported language version and
  public APIs.
- Do not report valid modern language syntax as an error when the project's
  language version supports it. Prefer framing such feedback as readability
  guidance, not correctness guidance.
- Verify the docs site still builds successfully after changes when doc changes
  are material.

## Good Review Targets

- accidental public helpers or leaked internal classes
- incorrect or incomplete state-machine invariants
- memory growth from normalization or cache behavior
- cross-package contract drift
- adapter assumptions not supported by the core
- stale or contradictory docs
- examples that do not match actual supported APIs
- ambiguous error messages that hinder debugging
- duplicate or redundant logic that reduces clarity
- incomplete test coverage for validation paths
- TOCTOU races (state changes between check and action)
- unreachable code paths (blocking operations prevent fallthrough)
- error handling side effects (rescue/retry creates new problems)
- type flow mismatches (interface accepts X, validation expects Y, code needs Z)
- validation-after-normalization (validates default instead of input)
- non-runnable documentation examples (prerequisites missing, incompatible
  options)
- inconsistent visibility scoping (some internal constants public)
- deep inheritance hierarchies instead of composition
- God objects mixing logic, IO, and orchestration
- global mutable state without synchronization or documentation
- implicit environment dependencies in non-CLI code
- hardcoded behavior where strategy pattern would allow pluggability
- missing instrumentation hooks on significant runtime events
- heavy meta-programming that hides control flow
- resources opened without cleanup paths (threads, sockets, files)
- interning unbounded user input (symbol table / memory growth)
- premature abstractions or indirection without demonstrated need
- undocumented concurrency contracts on thread/process-sensitive components

## Low-Value Review Targets

- formatting issues already covered by automated linting in CI
- speculative product objections when the change is internally consistent
- complaints that future-state docs are not yet fully implemented unless they
  contradict explicit support boundaries
- suggesting Service/Command pattern where a constructor + method is already
  clear and explicit
- requesting namespace renames purely for convention when existing names are
  unambiguous
- flagging file count or line count without identifying a specific
  responsibility violation
