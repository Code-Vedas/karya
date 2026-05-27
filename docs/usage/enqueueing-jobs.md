---
title: Enqueueing Jobs
parent: Usage
nav_parent: Usage
nav_order: 2
permalink: /usage/enqueueing-jobs/
---

# Enqueueing Jobs

Karya’s main enqueue surface is the framework-native job class. Define the job
once, then use `perform_later` for ordinary calls and `.set(...).perform_later`
when the caller must supply queueing metadata such as idempotency and
uniqueness keys.

{% capture enqueue_rails %}
```ruby
class BillingSyncJob < ApplicationJob
  queue_as :billing
  idempotent_by { |account_id, **| "billing-sync-#{account_id}" }
  unique_by(scope: :billing) { |account_id, **| "billing-#{account_id}" }

  def perform(account_id, force: false)
  end
end

BillingSyncJob.perform_later(42, force: true)

BillingSyncJob.set(
  queue: :critical_billing,
  job_id: "billing-sync-42",
  idempotency_key: "billing-sync-42",
  uniqueness_key: "billing-42",
  uniqueness_scope: :billing
).perform_later(42, force: true)
```

```bash
bin/rails karya:work billing critical_billing
```
{% endcapture %}

{% capture enqueue_hanami %}
```ruby
class BillingSyncJob < ApplicationJob
  queue_as :billing
  idempotent_by { |account_id, **| "billing-sync-#{account_id}" }

  def perform(account_id, force: false)
  end
end

BillingSyncJob.perform_later(42, force: true)

BillingSyncJob.set(
  queue: :critical_billing,
  idempotency_key: "billing-sync-42"
).perform_later(42, force: true)
```

```bash
bundle exec hanami karya:work billing critical_billing
```
{% endcapture %}

{% capture enqueue_roda %}
```ruby
class BillingSyncJob < ApplicationJob
  queue_as :billing
  unique_by(scope: :billing) { |account_id, **| "billing-#{account_id}" }

  def perform(account_id, force: false)
  end
end

BillingSyncJob.perform_later(42, force: true)

BillingSyncJob.set(
  queue: :critical_billing,
  uniqueness_key: "billing-42",
  uniqueness_scope: :billing
).perform_later(42, force: true)
```

```bash
bundle exec rake karya:work[billing,critical_billing]
```
{% endcapture %}

{% capture enqueue_sinatra %}
```ruby
class BillingSyncJob < ApplicationJob
  queue_as :billing
  idempotent_by { |account_id, **| "billing-sync-#{account_id}" }

  def perform(account_id, force: false)
  end
end

BillingSyncJob.perform_later(42, force: true)

BillingSyncJob.set(
  queue: :critical_billing,
  idempotency_key: "billing-sync-42"
).perform_later(42, force: true)
```

```bash
bundle exec rake karya:work[billing,critical_billing]
```
{% endcapture %}

{% include tabs.html
  id="enqueue-complete"
  label="Enqueue examples"
  count=4
  title1="Rails"
  content1=enqueue_rails
  title2="Hanami"
  content2=enqueue_hanami
  title3="Roda"
  content3=enqueue_roda
  title4="Sinatra"
  content4=enqueue_sinatra
%}

## How It Works In Practice

The class models queue routing, executable handler identity, and argument
shape. `perform_later` is the ordinary app-facing path. `.set(...)` is for
callers that need stable ids, caller-managed dedupe, or queue overrides. Time-
based dispatch belongs to [Scheduling With Kaal](/scheduling-with-kaal/), not
to the main framework enqueue path.
