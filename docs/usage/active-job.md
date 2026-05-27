---
title: Active Job
parent: Usage
nav_parent: Usage
nav_order: 8
permalink: /usage/active-job/
---

# Active Job

Rails can use the Karya ActiveJob bridge when an app explicitly wants
ActiveJob semantics. For the main Karya-native path, use `Karya::Rails::Job`
instead.

Outside Rails, use the native Karya job base for that framework rather than
pretending ActiveJob exists there.

{% capture active_job_rails %}
```ruby
# config/application.rb
config.active_job.queue_adapter = Karya::Rails.active_job_queue_adapter

class BillingReminderJob < ActiveJob::Base
  queue_as :billing

  def perform(account_id)
  end
end

BillingReminderJob.perform_later(42)
```

```bash
bin/rails karya:work billing
```
{% endcapture %}

{% capture active_job_hanami %}
```ruby
class BillingReminderJob < ApplicationJob
  queue_as :billing

  def perform(account_id)
  end
end

BillingReminderJob.perform_later(42)
```

```bash
bundle exec hanami karya:work billing
```
{% endcapture %}

{% capture active_job_roda %}
```ruby
class BillingReminderJob < ApplicationJob
  queue_as :billing

  def perform(account_id)
  end
end

BillingReminderJob.perform_later(42)
```

```bash
bundle exec rake karya:work[billing]
```
{% endcapture %}

{% capture active_job_sinatra %}
```ruby
class BillingReminderJob < ApplicationJob
  queue_as :billing

  def perform(account_id)
  end
end

BillingReminderJob.perform_later(42)
```

```bash
bundle exec rake karya:work[billing]
```
{% endcapture %}

{% include tabs.html
  id="active-job-complete"
  label="Active job examples"
  count=4
  title1="Rails"
  content1=active_job_rails
  title2="Hanami"
  content2=active_job_hanami
  title3="Roda"
  content3=active_job_roda
  title4="Sinatra"
  content4=active_job_sinatra
%}

## How It Works In Practice

Rails apps can enqueue through ActiveJob and let Karya execute the serialized
payload through the Karya handler bridge. Frameworks outside Rails should use
their native Karya job classes directly.

## Transaction Boundaries

The ActiveJob bridge submits jobs to Karya immediately when the app enqueues
them. Rolling back the surrounding application database transaction does not
pull that job back out of Karya.

Use the bridge when the app wants ActiveJob compatibility. When a flow needs
job dispatch to happen only after the application transaction commits, place
the enqueue call at the commit boundary owned by the app.
