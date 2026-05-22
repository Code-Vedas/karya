---
title: Child Workflows
parent: Usage
nav_parent: Usage
nav_order: 13
permalink: /usage/child-workflows/
---

# Child Workflows

Child workflows let a parent workflow coordinate a nested workflow run while
keeping parent and child batches distinct. Karya persists the relationship and
provides a sync surface for child completion state.

{% capture child_workflows_rails %}
```ruby
class AuthorizePaymentJob < ApplicationJob
  queue_as :billing

  def perform(order_id)
  end
end

class CapturePaymentJob < ApplicationJob
  queue_as :billing

  def perform(order_id)
  end
end

class PaymentSubflowJob < ApplicationJob
  queue_as :billing

  def perform(order_id)
  end
end

module PaymentWorkflows
  extend Karya::Rails::Workflow::Source

  workflow :payment do
    step :authorize, job: AuthorizePaymentJob
    step :capture, job: CapturePaymentJob, depends_on: :authorize
  end
end

module CheckoutWorkflows
  extend Karya::Rails::Workflow::Source

  workflow :checkout do
    step :payment_subflow, job: PaymentSubflowJob, child_workflow: :payment
  end
end

Karya::Rails.register_workflows(CheckoutWorkflows, PaymentWorkflows)

Karya::Rails::Workflow.start(
  definition: :checkout,
  batch_id: :checkout_42,
  step_arguments: {
    payment_subflow: PaymentSubflowJob.arguments(42)
  }
)

Karya::Rails::Workflow.enqueue_child(
  parent_batch_id: :checkout_42,
  parent_step_id: :payment_subflow,
  definition: :payment,
  batch_id: :payment_42,
  step_arguments: {
    authorize: AuthorizePaymentJob.arguments(42),
    capture: CapturePaymentJob.arguments(42)
  },
  now: Time.now.utc
)

Karya::Rails::Workflow.sync_children(
  parent_batch_id: :checkout_42,
  now: Time.now.utc
)
```

```bash
bin/rails karya:work billing
```
{% endcapture %}

{% capture child_workflows_hanami %}
```ruby
class AuthorizePaymentJob < ApplicationJob
  queue_as :billing

  def perform(order_id)
  end
end

class CapturePaymentJob < ApplicationJob
  queue_as :billing

  def perform(order_id)
  end
end

class PaymentSubflowJob < ApplicationJob
  queue_as :billing

  def perform(order_id)
  end
end

module PaymentWorkflows
  extend Karya::Hanami::Workflow::Source

  workflow :payment do
    step :authorize, job: AuthorizePaymentJob
    step :capture, job: CapturePaymentJob, depends_on: :authorize
  end
end

module CheckoutWorkflows
  extend Karya::Hanami::Workflow::Source

  workflow :checkout do
    step :payment_subflow, job: PaymentSubflowJob, child_workflow: :payment
  end
end

Karya::Hanami.register_workflows(CheckoutWorkflows, PaymentWorkflows)

Karya::Hanami::Workflow.start(
  definition: :checkout,
  batch_id: :checkout_42,
  step_arguments: {
    payment_subflow: PaymentSubflowJob.arguments(42)
  }
)

Karya::Hanami::Workflow.enqueue_child(
  parent_batch_id: :checkout_42,
  parent_step_id: :payment_subflow,
  definition: :payment,
  batch_id: :payment_42,
  step_arguments: {
    authorize: AuthorizePaymentJob.arguments(42),
    capture: CapturePaymentJob.arguments(42)
  },
  now: Time.now.utc
)
```

```bash
bundle exec hanami karya:work billing
```
{% endcapture %}

{% capture child_workflows_roda %}
```ruby
Karya::Roda::Workflow.start(
  definition: :checkout,
  batch_id: :checkout_42,
  step_arguments: {
    payment_subflow: PaymentSubflowJob.arguments(42)
  }
)

Karya::Roda::Workflow.enqueue_child(
  parent_batch_id: :checkout_42,
  parent_step_id: :payment_subflow,
  definition: :payment,
  batch_id: :payment_42,
  step_arguments: {
    authorize: AuthorizePaymentJob.arguments(42),
    capture: CapturePaymentJob.arguments(42)
  },
  now: Time.now.utc
)

Karya::Roda::Workflow.sync_children(
  parent_batch_id: :checkout_42,
  now: Time.now.utc
)
```

```bash
bundle exec rake karya:work[billing]
```
{% endcapture %}

{% capture child_workflows_sinatra %}
```ruby
Karya::Sinatra::Workflow.start(
  definition: :checkout,
  batch_id: :checkout_42,
  step_arguments: {
    payment_subflow: PaymentSubflowJob.arguments(42)
  }
)

Karya::Sinatra::Workflow.enqueue_child(
  parent_batch_id: :checkout_42,
  parent_step_id: :payment_subflow,
  definition: :payment,
  batch_id: :payment_42,
  step_arguments: {
    authorize: AuthorizePaymentJob.arguments(42),
    capture: CapturePaymentJob.arguments(42)
  },
  now: Time.now.utc
)

Karya::Sinatra::Workflow.sync_children(
  parent_batch_id: :checkout_42,
  now: Time.now.utc
)
```

```bash
bundle exec rake karya:work[billing]
```
{% endcapture %}

{% include tabs.html
  id="child-workflows-complete"
  label="Child workflow examples"
  count=4
  title1="Rails"
  content1=child_workflows_rails
  title2="Hanami"
  content2=child_workflows_hanami
  title3="Roda"
  content3=child_workflows_roda
  title4="Sinatra"
  content4=child_workflows_sinatra
%}

## How It Works In Practice

Treat child workflows as named product-level subflows with their own batch ids.
Start the parent workflow, enqueue the child workflow when the parent step must
fan out into a nested process, then call `sync_children` when the parent needs
to refresh child completion state before it continues.
