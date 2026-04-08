---
title: CLI
parent: Operator
nav_order: 3
permalink: /operator/cli/
---

# CLI

The CLI is the scripting-friendly operator surface for local tasks,
investigation, and automation.

## Covered Behavior

- runtime inspection
- lifecycle control
- automation-friendly operational commands
- alignment with the same queue, workflow, and schedule vocabulary used by the
  UI and APIs

## Common Scenarios

### Scripting An Operator Workflow

CLI workflows should mirror the same operational concepts shown in the
dashboard and operator APIs:

```text
karya queue inspect billing
karya workflow replay invoice-closeout-204
karya schedule pause nightly-reconciliation
```

These examples show the vocabulary and workflow shape operators should expect
across Karya surfaces.

## Runtime Bootstrap And Control

Runtime-oriented CLI flows use the supervisor-managed worker model:

```text
karya worker billing \
  --processes 1 \
  --threads 1 \
  --state-file /tmp/karya-runtime-billing.json \
  --env-prefix billing_worker \
  --worker-id worker-1 \
  --handler billing_sync=BillingJob
karya runtime inspect --state-file /tmp/karya-runtime-billing.json
karya runtime show --state-file /tmp/karya-runtime-billing.json
karya runtime drain --state-file /tmp/karya-runtime-billing.json
karya runtime force-stop --state-file /tmp/karya-runtime-billing.json
```

The worker supervisor writes a versioned JSON runtime state file. The runtime
CLI reads that file for inspection and uses the recorded local Unix control
socket plus instance token for drain or force-stop requests. `inspect` and
`show` describe the same inspection workflow. Process and thread defaults can
also be sourced from env-prefixed settings such as
`KARYA_BILLING_WORKER_PROCESSES` and `KARYA_BILLING_WORKER_THREADS`.

## Related Concepts

- [Controls](/runtime/controls/): CLI commands express the same control
  model
- [Replay](/workflows/replay/): workflow recovery should look familiar in
  CLI form
- [Activity And Audit](/operator/activity-audit/): CLI actions still need operator
  history
