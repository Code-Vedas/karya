# Karya PR Review Instructions

Use these instructions when reviewing pull requests in this repository. Favor
high-signal semantic review over generic style feedback.

## Future-State Docs

- Treat the root `README.md` files and everything under `docs/` as future-state
  product documentation.
- Do not flag a PR just because the documentation describes product capability
  that is not yet fully present in code.
- Do flag contradictions, stale names, broken links, impossible workflows, or
  claims that conflict with explicit repository structure and documented support
  boundaries.

## Required Review Checks

- Run secret scan checks.
- Run performance and security review checks.
- Run semantic and logic-error review checks.
- Run spelling and grammar checks.
- Do not spend review effort on lint-only feedback in this workflow. Linting is
  already handled elsewhere.

## Review Priorities

- Check internal consistency across `README.md` files and `docs/`.
- Check that framework, backend, dashboard, and operator guidance agree with one
  another.
- Check that optional versus first-class behavior is described clearly.
- Check for contradictions, unsupported assumptions, broken references, and weak
  review reasoning.

## Ruby And Package Review Rules

- Treat changes under `core/*/lib/` and `gems/*/lib/` as package contract work
  unless the code is clearly marked private.
- Treat changes in adapter or framework packages as cross-package contract work.
  Review for drift against the canonical runtime vocabulary in `core/karya/`
  and against the public guidance in docs and package READMEs.
- Review with the monorepo shape in mind:
  - canonical core runtime: `core/karya/`
  - backend cores: `core/karya-activerecord/`, `core/karya-sequel/`
  - framework gems: `gems/karya-rails/`, `gems/karya-sinatra/`,
    `gems/karya-roda/`, `gems/karya-hanami/`
  - dashboard gem: `gems/karya-dashboard/`
- Flag accidental API expansion. In particular:
  - helper methods exposed through `module_function`
  - helper constants or modules that become externally visible without intent
  - value-object helpers that leak internal normalization entrypoints
- Flag memory-risk normalization patterns. In particular:
  - `to_sym` on arbitrary user or application input
  - caches or registries that can grow from unbounded input
  - lookup paths that autovivify persistent containers on read
- Flag invariant gaps in returned runtime structures. In particular:
  - lifecycle maps that are not total over registered states
  - extension APIs that register states but leave derived views inconsistent
  - state-transition helpers that bypass validation or return partial views
- Flag cross-package compatibility gaps. In particular:
  - canonical lifecycle or queue vocabulary drifting between core packages,
    framework gems, dashboard surfaces, and docs
  - adapter packages or integration gems assuming behavior not guaranteed by the
    canonical core package
  - gem entrypoints exposing behavior inconsistent with package README guidance
- Flag stale-token, lease, queue, or reservation semantics that could break
  exclusivity, requeue guarantees, or worker safety.
- Prefer comments about behavior, API visibility, invariants, and memory
  characteristics over comments about formatting.

## Package-Specific Review Rules

- For `core/karya/`:
  - prioritize canonical runtime invariants, queue/job lifecycle semantics, and
    public API boundaries
- For `core/karya-activerecord/` and `core/karya-sequel/`:
  - prioritize adapter boundary clarity, persistence assumptions, and parity
    with the canonical core runtime contract
- For framework gems under `gems/`:
  - prioritize integration surface clarity, framework convention fit, and
    consistency with package-local README claims
- For `gems/karya-dashboard/`:
  - prioritize operator-surface consistency, internal API assumptions, asset
    packaging correctness, and alignment with documented runtime vocabulary

## Docs And Example Review Rules

- Verify local documentation links and navigation.
- Verify code snippets match the repository's supported Ruby version and public
  APIs.
- Do not report valid modern Ruby keyword shorthand as a syntax error when the
  repo's Ruby version supports it. Prefer framing such feedback as readability
  guidance, not correctness guidance.
- Verify the docs site still builds successfully after changes when doc changes
  are material.

## Good Review Targets

- accidental public helpers
- incorrect or incomplete lifecycle invariants
- memory growth from normalization or cache behavior
- cross-package contract drift
- adapter/framework assumptions not supported by the canonical core
- stale or contradictory docs
- examples that do not match actual supported APIs

## Low-Value Review Targets

- generic nitpicks already covered by `rubocop`, `reek`, or CI
- speculative product objections when the change is internally consistent
- complaints that future-state docs are not yet fully implemented unless they
  contradict explicit support boundaries
