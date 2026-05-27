---
title: Workflow Interactions
parent: Usage
nav_parent: Usage
nav_order: 11
permalink: /usage/workflow-interactions/
---

# Workflow Interactions

Workflow interaction surfaces let application code and operators pause runs,
resume them, deliver signals or events, approve checkpoints, query state, and
inspect workflow history.

{% capture workflow_interactions_rails %}
```ruby
class ReviewInvoiceJob < ApplicationJob
  queue_as :billing

  def perform(account_id)
  end
end

class PublishInvoiceJob < ApplicationJob
  queue_as :billing

  def perform(account_id)
  end
end

module BillingApprovalWorkflows
  extend Karya::Rails::Workflow::Source

  workflow :invoice_approval do
    step :review, job: ReviewInvoiceJob, wait_for_approval: :finance_review
    step :publish, job: PublishInvoiceJob, depends_on: :review
  end
end

Karya::Rails.register_workflows(BillingApprovalWorkflows)

Karya::Rails::Workflow.start(
  definition: :invoice_approval,
  batch_id: :invoice_approval_42,
  step_arguments: {
    review: ReviewInvoiceJob.arguments(42),
    publish: PublishInvoiceJob.arguments(42)
  }
)

Karya::Rails::Workflow.approve(
  batch_id: :invoice_approval_42,
  step_ids: [:review],
  now: Time.now.utc
)

state = Karya::Rails::Workflow.query(
  batch_id: :invoice_approval_42,
  query: :state,
  now: Time.now.utc
)

history = Karya::Rails::Workflow.history(
  batch_id: :invoice_approval_42,
  now: Time.now.utc
)
```

```bash
bin/rails karya:work billing
```
{% endcapture %}

{% capture workflow_interactions_hanami %}
```ruby
class ReviewInvoiceJob < ApplicationJob
  queue_as :billing

  def perform(account_id)
  end
end

class PublishInvoiceJob < ApplicationJob
  queue_as :billing

  def perform(account_id)
  end
end

module BillingApprovalWorkflows
  extend Karya::Hanami::Workflow::Source

  workflow :invoice_approval do
    step :review, job: ReviewInvoiceJob, wait_for_approval: :finance_review
    step :publish, job: PublishInvoiceJob, depends_on: :review
  end
end

Karya::Hanami.register_workflows(BillingApprovalWorkflows)

Karya::Hanami::Workflow.start(
  definition: :invoice_approval,
  batch_id: :invoice_approval_42,
  step_arguments: {
    review: ReviewInvoiceJob.arguments(42),
    publish: PublishInvoiceJob.arguments(42)
  }
)

Karya::Hanami::Workflow.pause(
  batch_id: :invoice_approval_42,
  now: Time.now.utc
)

Karya::Hanami::Workflow.resume(
  batch_id: :invoice_approval_42,
  now: Time.now.utc
)

state = Karya::Hanami::Workflow.query(
  batch_id: :invoice_approval_42,
  query: :state,
  now: Time.now.utc
)
```

```bash
bundle exec hanami karya:work billing
```
{% endcapture %}

{% capture workflow_interactions_roda %}
```ruby
class AllocateInventoryJob < ApplicationJob
  queue_as :fulfillment

  def perform(order_id)
  end
end

class ShipOrderJob < ApplicationJob
  queue_as :fulfillment

  def perform(order_id)
  end
end

module FulfillmentWorkflows
  extend Karya::Roda::Workflow::Source

  workflow :shipment_confirmation do
    step :allocate, job: AllocateInventoryJob
    step :ship, job: ShipOrderJob, depends_on: :allocate, wait_for_signal: :inventory_confirmed
  end
end

Karya::Roda.register_workflows(FulfillmentWorkflows)

Karya::Roda::Workflow.start(
  definition: :shipment_confirmation,
  batch_id: :shipment_confirmation_42,
  step_arguments: {
    allocate: AllocateInventoryJob.arguments(42),
    ship: ShipOrderJob.arguments(42)
  }
)

Karya::Roda::Workflow.signal(
  batch_id: :shipment_confirmation_42,
  signal: :inventory_confirmed,
  payload: { "source" => "warehouse" },
  now: Time.now.utc
)

history = Karya::Roda::Workflow.history(
  batch_id: :shipment_confirmation_42,
  now: Time.now.utc
)
```

```bash
bundle exec rake karya:work[fulfillment]
```
{% endcapture %}

{% capture workflow_interactions_sinatra %}
```ruby
class LoadLedgerJob < ApplicationJob
  queue_as :ledger

  def perform(account_id)
  end
end

class ReconcileLedgerJob < ApplicationJob
  queue_as :ledger

  def perform(account_id)
  end
end

module ReconciliationWorkflows
  extend Karya::Sinatra::Workflow::Source

  workflow :nightly_reconciliation do
    step :load, job: LoadLedgerJob
    step :reconcile, job: ReconcileLedgerJob, depends_on: :load, wait_for_event: :ledger_uploaded
  end
end

Karya::Sinatra.register_workflows(ReconciliationWorkflows)

Karya::Sinatra::Workflow.start(
  definition: :nightly_reconciliation,
  batch_id: :nightly_reconciliation_42,
  step_arguments: {
    load: LoadLedgerJob.arguments(42),
    reconcile: ReconcileLedgerJob.arguments(42)
  }
)

Karya::Sinatra::Workflow.event(
  batch_id: :nightly_reconciliation_42,
  event: :ledger_uploaded,
  payload: { "source" => "s3" },
  now: Time.now.utc
)

snapshot = Karya::Sinatra::Workflow.snapshot(
  batch_id: :nightly_reconciliation_42,
  now: Time.now.utc
)
```

```bash
bundle exec rake karya:work[ledger]
```
{% endcapture %}

{% include tabs.html
  id="workflow-interactions-complete"
  label="Workflow interaction examples"
  count=4
  title1="Rails"
  content1=workflow_interactions_rails
  title2="Hanami"
  content2=workflow_interactions_hanami
  title3="Roda"
  content3=workflow_interactions_roda
  title4="Sinatra"
  content4=workflow_interactions_sinatra
%}

## How It Works In Practice

Interaction calls only make sense against a real workflow batch. Start the
workflow first, then use `approve`, `signal`, `event`, `pause`, or `resume`
for that batch id. Follow the interaction with `query`, `snapshot`, or
`history` when you want to confirm the batch moved into the state you expected.
