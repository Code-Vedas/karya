---
title: Scheduling With Kaal
nav_order: 5
permalink: /scheduling-with-kaal/
---

# Scheduling With Kaal

Karya executes jobs and workflows after application code enqueues them. Kaal
owns recurring and scheduled dispatch. Use the matching Kaal framework package
when work should run because of a clock or cron expression.

## Boundary

- Karya owns enqueue, workers, workflows, runtime control, and reliability
- Kaal owns recurring and scheduled dispatch

{% capture kaal_rails %}
```ruby
class BillingCloseoutJob < Karya::Rails::Job
  queue_as :billing

  def perform(account_id, run_mode: "nightly")
  end
end
```

```yaml
# config/kaal.yml
defaults:
  backend: postgres
  backend_config:
    url: <%= ENV.fetch("DATABASE_URL") %>

development: {}
test: {}
production: {}
```

```yaml
# config/kaal-scheduler.yml
production:
  jobs:
    - key: "billing:closeout"
      cron: "0 2 * * *"
      job_class: "BillingCloseoutJob"
      args:
        - 42
      kwargs:
        run_mode: "nightly"
```
{% endcapture %}

{% capture kaal_hanami %}
```ruby
class BillingCloseoutJob < Karya::Hanami::Job
  queue_as :billing

  def perform(account_id, run_mode: "nightly")
  end
end
```

```yaml
# config/kaal.yml
defaults:
  backend: postgres
  backend_config:
    url: <%= ENV.fetch("DATABASE_URL") %>

development: {}
test: {}
production: {}
```

```yaml
# config/kaal-scheduler.yml
production:
  jobs:
    - key: "billing:closeout"
      cron: "0 2 * * *"
      job_class: "BillingCloseoutJob"
      args:
        - 42
      kwargs:
        run_mode: "nightly"
```
{% endcapture %}

{% capture kaal_roda %}
```ruby
class BillingCloseoutJob < Karya::Roda::Job
  queue_as :billing

  def perform(account_id, run_mode: "nightly")
  end
end
```

```yaml
# config/kaal.yml
defaults:
  backend: postgres
  backend_config:
    url: <%= ENV.fetch("DATABASE_URL") %>

development: {}
test: {}
production: {}
```

```yaml
# config/kaal-scheduler.yml
production:
  jobs:
    - key: "billing:closeout"
      cron: "0 2 * * *"
      job_class: "BillingCloseoutJob"
      args:
        - 42
      kwargs:
        run_mode: "nightly"
```
{% endcapture %}

{% capture kaal_sinatra %}
```ruby
class BillingCloseoutJob < Karya::Sinatra::Job
  queue_as :billing

  def perform(account_id, run_mode: "nightly")
  end
end
```

```yaml
# config/kaal.yml
defaults:
  backend: postgres
  backend_config:
    url: <%= ENV.fetch("DATABASE_URL") %>

development: {}
test: {}
production: {}
```

```yaml
# config/kaal-scheduler.yml
production:
  jobs:
    - key: "billing:closeout"
      cron: "0 2 * * *"
      job_class: "BillingCloseoutJob"
      args:
        - 42
      kwargs:
        run_mode: "nightly"
```
{% endcapture %}

{% include tabs.html
  id="kaal-frameworks"
  label="Kaal scheduling examples"
  count=4
  title1="Rails"
  content1=kaal_rails
  title2="Hanami"
  content2=kaal_hanami
  title3="Roda"
  content3=kaal_roda
  title4="Sinatra"
  content4=kaal_sinatra
%}

Kaal dispatches the configured job class on schedule, and Karya executes it
through the framework-native worker runtime.

Kaal loads scheduler state from `config/kaal.yml` and recurring definitions
from `config/kaal-scheduler.yml` through its file-based runtime API.

## Framework Packages

- Rails: `kaal-rails`
- Hanami: `kaal-hanami`
- Roda: `kaal-roda`
- Sinatra: `kaal-sinatra`

See `https://kaal.codevedas.com` for scheduler setup, guarantees, and runtime
operations.
