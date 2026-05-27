---
title: Retries, Uniqueness, And Reliability
parent: Usage
nav_parent: Usage
nav_order: 5
permalink: /usage/retries-uniqueness-and-reliability/
---

# Retries, Uniqueness, And Reliability

Karya lets job classes describe retry behavior, dedupe caller intent, and
shape queue pressure without leaving the framework-native job surface.

{% capture reliability_rails %}
```ruby
retry_policy = Karya::RetryPolicy.new(
  max_attempts: 5,
  base_delay: 5,
  multiplier: 2,
  max_delay: 300,
  jitter_strategy: :full
)

class BillingSyncJob < ApplicationJob
  queue_as :billing
  retry_with retry_policy
  idempotent_by { |account_id, **| "billing-sync-#{account_id}" }
  unique_by(scope: :billing) { |account_id, **| "billing-#{account_id}" }

  def perform(account_id, force: false)
  end
end

BillingSyncJob.perform_later(42, force: true)
```
{% endcapture %}

{% capture reliability_hanami %}
```yaml
# config/karya.yml
defaults:
  backend: postgres
  backend_config:
    url: <%= ENV.fetch("DATABASE_URL") %>
    policy_set:
      concurrency:
        "tenant:acme":
          limit: 1
      rate_limits:
        "handler:billing_sync_job":
          limit: 10
          period: 60
  job_paths:
    - app/jobs
  boot_files: []

development: {}
test: {}
production: {}
```

```bash
bundle exec hanami karya:work billing
```
{% endcapture %}

{% capture reliability_roda %}
```yaml
# config/karya.yml
defaults:
  backend: redis
  backend_config:
    url: <%= ENV.fetch("REDIS_URL") %>
    circuit_breakers:
      "queue:billing":
        failure_threshold: 5
        window: 60
        cooldown: 120
  job_paths:
    - app/jobs
  boot_files: []

development: {}
test: {}
production: {}
```
{% endcapture %}

{% capture reliability_sinatra %}
```yaml
# config/karya.yml
defaults:
  backend: sqlite
  backend_config:
    url: <%= ENV.fetch("DATABASE_URL") %>
    fairness_policy:
      strategy: round_robin
  job_paths:
    - app/jobs
  boot_files: []

development: {}
test: {}
production: {}
```
{% endcapture %}

{% include tabs.html
  id="reliability-complete"
  label="Reliability examples"
  count=4
  title1="Rails"
  content1=reliability_rails
  title2="Hanami"
  content2=reliability_hanami
  title3="Roda"
  content3=reliability_roda
  title4="Sinatra"
  content4=reliability_sinatra
%}

## How It Works In Practice

Retry policy decides how failed jobs re-enter runnable state. Idempotency keys
reject duplicate caller intent. Uniqueness keys reject conflicting active or
queued work. Backpressure, circuit-breaker, and fairness policies shape worker
behavior at reservation time rather than forcing app teams to build their own
queue-control layer.
