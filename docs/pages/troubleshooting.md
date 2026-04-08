---
title: Troubleshooting
nav_order: 14
permalink: /troubleshooting/
---

# Troubleshooting

Use this page to triage repository setup, dashboard packaging, runtime
operations, and integration problems.

It is organized around the failures people hit first: setup drift, missing
dashboard assets, stuck work, route mismatches, and policy blocks.

The fastest way to use this page is to identify the symptom first, then jump to
the part of the platform that owns it: host setup, dashboard delivery, runtime
behavior, backend behavior, or governed access.

## Common Starting Points

- if the UI does not render, start with dashboard packaging and host routing
- if work is delayed or stuck, start with runtime, reliability, and backend
  state
- if an action is blocked, start with governance, identity, and policy state
- if operators cannot explain what happened, start with observability and audit
  surfaces

## Setup Problems

### Dependency Installation Fails

- rerun `scripts/ci-install-bundles` from the repository root
- confirm Ruby, Node, and Yarn are available in the local environment
- use package-local install commands only when intentionally working on one
  package in isolation

### Common Scenario

```text
symptom: repository checks fail immediately after clone
first checks: install bundles, Ruby/Node/Yarn availability, package-local drift
next move: rerun the shared setup path from the repo root
```

## Dashboard Packaging Problems

### Missing `asset-manifest.json`

Run the packaging flow in `gems/karya-dashboard`:

```bash
bin/prepackage-build
```

This rebuilds the dashboard assets and regenerates the manifest required by the
host renderers.

### Broken Asset URLs

Check:

- the configured `asset_prefix`
- whether the host is serving `dist/assets/*`
- whether the mount path and asset prefix are aligned with the served route

### Common Scenario

```text
symptom: dashboard HTML renders but styles or scripts are missing
first checks: asset manifest, asset prefix, served dist assets
next move: verify host route and asset path alignment
```

## Runtime And Operator Problems

When work is stuck, backlogged, or repeatedly failing, review:

- queue pause/resume state
- supervisor runtime state and worker topology
- rate-limit or concurrency-group conditions
- dead-letter or poison-job status
- workflow checkpoint, replay, or approval state
- backend-specific caveats documented in the support matrix

### Common Scenario

```text
symptom: queue grows while operators see little progress
first checks: queue pause state, supervisor phase, worker activity, concurrency or rate limits
next move: confirm whether the issue is pressure, drain behavior, failure, or backend behavior
```

### Runtime Inspection Checklist

When diagnosing worker-runtime problems, confirm:

- the runtime state file exists, is current, and belongs to the intended
  supervisor
- `karya runtime inspect --state-file <path>` shows the expected supervisor
  phase, process count, and thread count
- `child_processes` and thread state reflect the expected runtime topology
- the selected queue store is safe for the configured process and thread
  settings
- shutdown behavior matches operator intent, especially during drain and
  forced-stop escalation

## Framework Integration Problems

Look for:

- route mismatches between the host and documented mount path
- auth/session integration drift preventing dashboard access
- missing framework-specific operator API exposure
- backend or adapter mismatch for the selected host package

### Common Scenario

```text
symptom: host boots, but the dashboard route or operator surface behaves incorrectly
first checks: mount path, route ownership, session/auth behavior, adapter pairing
next move: compare the host against the framework and hosting docs
```

## Governance And Access Problems

If an operator action is rejected or hidden:

- verify the active RBAC or ABAC policy context
- check tenant or namespace scoping
- confirm whether policy simulation, approval, or release-channel rules apply

### Common Scenario

```text
symptom: operator can see a resource but cannot act on it
first checks: policy result, tenant scope, approval state, release-channel controls
next move: confirm whether the block is intentional before treating it as a bug
```

## Escalate By Area

- [Dashboard Hosting](/dashboard-hosting/): asset delivery, mount path, and host
  rendering problems
- [Backends](/backends/): backend fit, parity caveats, and persistence tradeoffs
- [Runtime](/runtime/): job, worker, and control-surface behavior
- [Reliability](/reliability/): retries, backpressure, uniqueness, and
  dead-letter flows
- [Workflows](/workflows/): replay, signals, checkpoints, and workflow
  recovery
- [Operator](/operator/): drilldowns, search, audit, and internal API
  issues
- [Governance](/governance/): identity, policy, tenant boundaries, and
  rollout controls
- [Observability](/observability/): traces, logs, metrics, and health surfaces
