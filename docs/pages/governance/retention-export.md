---
title: Retention And Export
parent: Governance
nav_order: 5
permalink: /governance/retention-export/
---

# Retention And Export

Karya documents data-lifecycle controls as part of the operator and compliance
story.

## Covered Behavior

- retention controls
- export packages
- redaction support
- legal-hold protections
- audit coverage and encryption hooks

## Common Scenarios

### Handling Protected Data

Data-governance operations should show clear safety boundaries:

```text
resource: workflow-history
retention_policy: 90-days
legal_hold: active
export_request: blocked
reason: protected-resource
```

Retention, export, and protection outcomes should be explicit before anyone
tries to act on protected data.

## Related Concepts

- [Policies](/governance/policies/): access controls and data-lifecycle rules intersect
- [Activity And Audit](/operator/activity-audit/): export and protection
  actions need clear history
- [Backends](/backends/): persistence choices affect how these controls are
  implemented and reasoned about
