---
title: Workflows
parent: Usage
nav_parent: Usage
nav_order: 10
permalink: /usage/workflows/
---

# Workflows

Karya workflows use framework-native Ruby DSLs to define step graphs,
dependencies, compensation paths, workflow families, and versioned catalogs.
Jobs remain the executable units; workflows decide when those jobs should run.

{% capture workflows_rails %}
```ruby
class CalculateTotalsJob < ApplicationJob
  queue_as :billing

  def perform(account_id)
  end
end

class CapturePaymentJob < ApplicationJob
  queue_as :billing

  def perform(account_id)
  end
end

class EmitReceiptJob < ApplicationJob
  queue_as :billing

  def perform(account_id)
  end
end

module BillingWorkflows
  extend Karya::Rails::Workflow::Source

  workflow :invoice_closeout, workflow_family: :billing_closeout, workflow_version: :v2 do
    step :calculate_totals, job: CalculateTotalsJob
    step :capture_payment, job: CapturePaymentJob, depends_on: :calculate_totals
    step :emit_receipt, job: EmitReceiptJob, depends_on: :capture_payment
  end
end

Karya::Rails.register_workflows(BillingWorkflows)

Karya::Rails::Workflow.start(
  definition: :invoice_closeout,
  batch_id: :invoice_closeout_42,
  step_arguments: {
    calculate_totals: CalculateTotalsJob.arguments(42),
    capture_payment: CapturePaymentJob.arguments(42),
    emit_receipt: EmitReceiptJob.arguments(42)
  }
)
```

```bash
bin/rails karya:work billing
```
{% endcapture %}

{% capture workflows_hanami %}
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

module BillingWorkflows
  extend Karya::Hanami::Workflow::Source

  workflow :invoice_review do
    step :review, job: ReviewInvoiceJob
    step :publish, job: PublishInvoiceJob, depends_on: :review
  end
end

Karya::Hanami.register_workflows(BillingWorkflows)

Karya::Hanami::Workflow.start(
  definition: :invoice_review,
  batch_id: :invoice_review_42,
  step_arguments: {
    review: ReviewInvoiceJob.arguments(42),
    publish: PublishInvoiceJob.arguments(42)
  }
)
```

```bash
bundle exec hanami karya:work billing
```
{% endcapture %}

{% capture workflows_roda %}
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

  workflow :fulfillment do
    step :allocate, job: AllocateInventoryJob
    step :ship, job: ShipOrderJob, depends_on: :allocate
  end
end

Karya::Roda.register_workflows(FulfillmentWorkflows)

Karya::Roda::Workflow.start(
  definition: :fulfillment,
  batch_id: :fulfillment_42,
  step_arguments: {
    allocate: AllocateInventoryJob.arguments(42),
    ship: ShipOrderJob.arguments(42)
  }
)
```

```bash
bundle exec rake karya:work[fulfillment]
```
{% endcapture %}

{% capture workflows_sinatra %}
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
    step :reconcile, job: ReconcileLedgerJob, depends_on: :load
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
```

```bash
bundle exec rake karya:work[ledger]
```
{% endcapture %}

{% include tabs.html
  id="workflows-complete"
  label="Workflow lifecycle examples"
  count=4
  title1="Rails"
  content1=workflows_rails
  title2="Hanami"
  content2=workflows_hanami
  title3="Roda"
  content3=workflows_roda
  title4="Sinatra"
  content4=workflows_sinatra
%}

## How It Works In Practice

`definition` identifies the registered workflow to run. `batch_id` identifies
one concrete workflow execution. `step_arguments` supplies the per-step job
inputs through `Job.arguments(...)`, which lets Karya persist workflow metadata
separately from executable job payloads. Keep the worker running for the queues
used by the step job classes, or the workflow will start but no step jobs will
execute.
