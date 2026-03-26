---
title: Policies
parent: Governance
nav_order: 2
permalink: /governance/policies/
---

# Policies

Governed operations depend on explicit policy behavior.

## Covered Behavior

- RBAC and ABAC models
- policy simulation
- governed action scoping
- interoperability expectations for external policy engines

## Common Scenarios

### Evaluating A Governed Action

Policy behavior should be understandable before an action is taken:

```text
action: replay workflow invoice-closeout-204
actor_role: operator
tenant: north-america
policy_result: denied
reason: approval-required
```

Policy outcomes should be explainable and able to feed simulation or approval
flows.

## Related Concepts

- [Identity](/governance/identity/): policy starts from authenticated operator identity
- [Rollout](/governance/rollout/): approvals and release controls often use the same
  policy model
- [Activity And Audit](/operator/activity-audit/): policy decisions should
  remain visible later
