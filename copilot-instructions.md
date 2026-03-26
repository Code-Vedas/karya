# Copilot Instructions

Use these instructions to keep reviews focused on the highest-value signals in
this repository.

## Future-State Docs

- Treat the root `README.md` files and everything under `docs/` as future-state
  product documentation when reviewing any PR.
- Do not flag a PR just because the documentation describes product capability
  that is not yet fully present in code.
- Do flag contradictions, stale names, broken links, impossible workflows, or
  claims that conflict with explicit repository structure and documented support
  boundaries.

## Required Review Checks

- Run a secret scan.
- Run performance and security review checks.
- Run semantic and logic-error review checks.
- Run spelling and grammar checks.
- Do not spend review effort on linting code in this workflow. Code linting is
  already handled elsewhere.

## Review Priorities

- Check internal consistency across `README.md` files and `docs/`.
- Check that framework, backend, dashboard, and operator guidance agree with one
  another.
- Check that optional versus first-class behavior is described clearly.
- Check for contradictions, unsupported assumptions, broken references, and weak
  review reasoning.

## Additional Useful Checks

- Verify local documentation links and navigation.
- Verify the docs site still builds successfully after changes.
