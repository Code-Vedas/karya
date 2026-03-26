---
title: Identity
parent: Governance
nav_order: 1
permalink: /governance/identity/
---

# Identity

Karya documents OIDC/OAuth2 and SAML as first-class identity options for
operator access.

## Covered Behavior

- standards-based identity integration
- session-aware operator access
- framework-aligned authentication boundaries
- integration expectations for dashboard and operator workflows

## Common Scenarios

### Granting Operator Access

Identity should make operator access boundaries explicit:

```text
identity_provider: corporate-sso
protocol: oidc
user: alice@example.com
granted_access: operator-dashboard
session_policy: standard-admin
```

Identity defines who gets into operator surfaces and under which session policy.

## Related Concepts

- [Policies](/governance/policies/): identity and authorization decisions work together
- [Dashboard](/operator/dashboard/): operator access starts here in practice
- [Rollout](/governance/rollout/): governed operations depend on the right identity model
