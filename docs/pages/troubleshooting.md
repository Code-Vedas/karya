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

- routing and worker subscription alignment
- supervisor runtime state and worker topology
- queue pause/resume state before treating queued work as stuck
- circuit-breaker state, cooldown windows, and stuck-job recovery inspection
- retry, rate-limit, or concurrency-group conditions
- dead-letter isolation snapshots, recovery action availability, and isolation
  reasons before retrying or replaying work
- workflow replay, checkpoint, or approval state
- backend-specific caveats documented in the support matrix

### Common Scenario

```text
symptom: queue grows while operators see little progress
first checks: routing match, paused queue state, supervisor phase, worker activity, circuit-breaker state, concurrency or rate limits
next move: confirm whether the issue is intentional pause, pressure, a breaker-open path, routing mismatch, retry churn, or backend behavior
```

### Runtime Inspection Checklist

When diagnosing worker-runtime problems, confirm:

- the runtime state file exists, is current, and belongs to the intended
  supervisor
- `karya runtime inspect --state-file <path>` shows the expected supervisor
  phase, process count, and thread count
- `child_processes` and thread state reflect the expected runtime topology
- queue controls show whether reservation has been paused for the queue
- reliability inspection distinguishes breaker-open queues from ordinary
  concurrency or rate-limit pressure
- stuck-job inspection shows whether running leases were automatically
  recovered back into queued work
- the selected queue store is safe for the configured process and thread
  settings
- shutdown behavior matches operator intent, especially during drain and
  forced-stop escalation

## Workflow Problems

Workflow triage starts with the workflow snapshot. Batch snapshots explain
membership and aggregate job state; workflow snapshots explain orchestration
state, step readiness, blocking prerequisites, and rollback metadata.

### Dependent Step Does Not Reserve

Check the dependent step snapshot before treating the queue as stuck:

```text
symptom: emit_receipt stays queued
first checks: workflow_snapshot.fetch_step(:emit_receipt).prerequisite_states
next move: confirm every prerequisite job is succeeded
```

Reserved, running, queued, retry-pending, failed, dead-lettered, and cancelled
prerequisites do not unblock dependent steps. A recovered prerequisite must
succeed before children become eligible.

### Workflow Is Failed

Use `workflow_snapshot` to identify the step that moved the workflow into
failed state:

```text
symptom: workflow state is failed
first checks: step_states, failed_count, dead-lettered steps, rollback_requested?
next move: choose explicit step recovery or explicit rollback
```

A workflow can be failed because one primary step is `failed` or
`dead_letter`, or because terminal mixed outcomes prevent workflow success.
Use explicit step ids for retry, replay, controlled retry, or discard. Karya
does not infer target steps from workflow state.

Rollback is only accepted after the workflow is `:failed` and no active or
dependency-ready queued work remains. If the snapshot still shows reserved,
running, retry-pending, or runnable queued steps, stop, complete, or recover
that work before expecting rollback to succeed.

### Replay Or Retry Did Not Unblock Children

Replay and retry only recover the target primary step job into normal
execution. They do not mark the prerequisite as successful:

```text
symptom: child still blocked after replay_workflow_steps
first checks: recovered parent step state, reservation eligibility, next_retry_at
next move: run the recovered parent to succeeded, then inspect the child step again
```

For dead-lettered work, `replay_workflow_steps` returns the step to `queued`;
`retry_dead_letter_workflow_steps` returns it to `retry_pending` until the
configured retry time. Dependents unblock only after the parent succeeds.

### Child Workflow Step Does Not Reserve

Child workflow parent steps are gate jobs. They wait for the child workflow to
succeed before workers can reserve the parent-side step:

```text
symptom: parent child step stays queued
first checks: workflow_snapshot.fetch_step(:payment).child_workflow_id, workflow_snapshot.fetch_step(:payment).child_workflow
next move: if child_workflow is nil, enqueue or register the declared child workflow; otherwise inspect and recover it by child_batch_id
```

If the child workflow is failed or cancelled, run `sync_child_workflows` against
the parent batch to propagate that terminal state to the parent gate job. Sync
does not roll back either workflow automatically.

### Rollback Has No Batch To Inspect

No-op rollback is valid when every succeeded primary step is uncompensated:

```text
symptom: rollback_requested? is true but batch_snapshot(rollback_batch_id) is unknown
first checks: rollback.compensation_job_ids, rollback.compensation_count
next move: treat the rollback boundary as recorded when compensation_count is zero
```

Rollback metadata is still inspectable from the workflow snapshot. A physical
rollback batch exists only when compensation jobs were enqueued.

### Compensation Runs One Job At A Time

Compensation jobs are dependency-gated so rollback happens in reverse workflow
definition order:

```text
symptom: later compensation job is queued but not reserving
first checks: rollback batch job states, earlier compensation job state
next move: complete or recover the earlier compensation job
```

Compensation jobs are ordinary queue-store jobs. If a compensation job fails or
is dead-lettered, use the normal job recovery controls for that rollback batch
job before expecting the next compensation job to reserve.

### Batch State And Workflow State Differ

Batch aggregate state and workflow state answer different questions:

```text
symptom: batch aggregate and workflow state do not match
first checks: batch_snapshot.aggregate_state, workflow_snapshot.state
next move: use workflow state for orchestration decisions and batch state for member-job summaries
```

Batch state summarizes current member job lifecycle states. Workflow state adds
orchestration meaning: pending roots, blocked dependents, failed prerequisites,
eligible follow-up work, and rollback request metadata.

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
- [Workflow Examples](/workflows/examples/): concrete workflow recovery and
  rollback scenarios
- [Operator](/operator/): drilldowns, search, audit, and internal API
  issues
- [Governance](/governance/): identity, policy, tenant boundaries, and
  rollout controls
- [Observability](/observability/): traces, logs, metrics, and health surfaces
