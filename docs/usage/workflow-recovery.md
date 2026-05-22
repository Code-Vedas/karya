---
title: Workflow Recovery
parent: Usage
nav_parent: Usage
nav_order: 12
permalink: /usage/workflow-recovery/
---

# Workflow Recovery

Workflow recovery controls act on step identities inside a workflow batch.
They are the operator path for retrying failed work, isolating broken steps,
replaying dead-lettered steps, and rolling back a workflow intentionally.

{% capture workflow_recovery_rails %}
```ruby
snapshot = Karya::Rails::Workflow.snapshot(
  batch_id: :invoice_closeout_42,
  now: Time.now.utc
)

history = Karya::Rails::Workflow.history(
  batch_id: :invoice_closeout_42,
  now: Time.now.utc
)

Karya::Rails::Workflow.retry_steps(
  batch_id: :invoice_closeout_42,
  step_ids: [:capture_payment],
  now: Time.now.utc
)

latest_state = Karya::Rails::Workflow.query(
  batch_id: :invoice_closeout_42,
  query: :state,
  now: Time.now.utc
)
```
{% endcapture %}

{% capture workflow_recovery_hanami %}
```ruby
snapshot = Karya::Hanami::Workflow.snapshot(
  batch_id: :invoice_review_42,
  now: Time.now.utc
)

Karya::Hanami::Workflow.dead_letter_steps(
  batch_id: :invoice_review_42,
  step_ids: [:review],
  reason: "external dependency outage",
  now: Time.now.utc
)

Karya::Hanami::Workflow.retry_dead_letter_steps(
  batch_id: :invoice_review_42,
  step_ids: [:review],
  next_retry_at: Time.now.utc + 300,
  now: Time.now.utc
)
```
{% endcapture %}

{% capture workflow_recovery_roda %}
```ruby
history = Karya::Roda::Workflow.history(
  batch_id: :fulfillment_42,
  now: Time.now.utc
)

Karya::Roda::Workflow.replay_steps(
  batch_id: :fulfillment_42,
  step_ids: [:ship],
  now: Time.now.utc
)

Karya::Roda::Workflow.discard_steps(
  batch_id: :fulfillment_42,
  step_ids: [:ship],
  now: Time.now.utc
)
```
{% endcapture %}

{% capture workflow_recovery_sinatra %}
```ruby
snapshot = Karya::Sinatra::Workflow.snapshot(
  batch_id: :nightly_reconciliation_42,
  now: Time.now.utc
)

Karya::Sinatra::Workflow.rollback(
  batch_id: :nightly_reconciliation_42,
  reason: "operator rollback after validation failure",
  now: Time.now.utc
)

history = Karya::Sinatra::Workflow.history(
  batch_id: :nightly_reconciliation_42,
  now: Time.now.utc
)
```
{% endcapture %}

{% include tabs.html
  id="workflow-recovery-complete"
  label="Workflow recovery examples"
  count=4
  title1="Rails"
  content1=workflow_recovery_rails
  title2="Hanami"
  content2=workflow_recovery_hanami
  title3="Roda"
  content3=workflow_recovery_roda
  title4="Sinatra"
  content4=workflow_recovery_sinatra
%}

## How It Works In Practice

Inspect `snapshot` or `history` first so recovery is based on the actual failed
step set. Use `retry_steps` when the same step should run again, `dead_letter`
when work must be isolated from the main workflow path, `replay` when isolated
work should run again, `discard` when the step must stop permanently, and
`rollback` when the workflow should trigger compensating behavior intentionally.
