---
title: Getting Started
parent: Usage
nav_parent: Usage
nav_order: 1
permalink: /usage/getting-started/
---

# Getting Started

After installation, the first successful Karya setup has five moving parts:

1. framework package and backend config
2. `ApplicationJob`
3. one concrete job class
4. one enqueue call
5. one worker command for the target queue

Use [Install](/install/) for the package and bootstrap flow. This page shows
the first complete app-facing path after that install step.

Examples use each framework's native command surface: `bin/rails` for Rails,
`bundle exec hanami` for Hanami, and `bundle exec rake` for Roda and Sinatra.

{% capture getting_started_rails %}
```ruby
```

```yaml
# config/karya.yml
defaults:
  backend: postgres
  backend_config:
    url: <%= ENV.fetch("DATABASE_URL") %>
  job_paths:
    - app/jobs
  boot_files: []

development: {}
test: {}
production: {}
```

```ruby

class ApplicationJob < Karya::Rails::Job
  abstract!
end

class BillingSyncJob < ApplicationJob
  queue_as :billing

  def perform(account_id, force: false)
  end
end

BillingSyncJob.perform_later(42, force: true)
```

```bash
bin/rails karya:work billing --processes 1 --threads 4
bin/rails karya:runtime inspect billing
```
{% endcapture %}

{% capture getting_started_hanami %}
```ruby
```

```yaml
# config/karya.yml
defaults:
  backend: postgres
  backend_config:
    url: <%= ENV.fetch("DATABASE_URL") %>
  job_paths:
    - app/jobs
  boot_files: []

development: {}
test: {}
production: {}
```

```ruby

class ApplicationJob < Karya::Hanami::Job
  abstract!
end

class BillingSyncJob < ApplicationJob
  queue_as :billing

  def perform(account_id, force: false)
  end
end

BillingSyncJob.perform_later(42, force: true)
```

```bash
bundle exec hanami karya:work billing --processes 1 --threads 4
bundle exec hanami karya:runtime inspect billing
```
{% endcapture %}

{% capture getting_started_roda %}
```ruby
```

```yaml
# config/karya.yml
defaults:
  backend: postgres
  backend_config:
    url: <%= ENV.fetch("DATABASE_URL") %>
  job_paths:
    - app/jobs
  boot_files: []

development: {}
test: {}
production: {}
```

```ruby

class ApplicationJob < Karya::Roda::Job
  abstract!
end

class BillingSyncJob < ApplicationJob
  queue_as :billing

  def perform(account_id, force: false)
  end
end

BillingSyncJob.perform_later(42, force: true)
```

```bash
bundle exec rake karya:work[billing]
bundle exec rake karya:runtime:inspect[billing]
```
{% endcapture %}

{% capture getting_started_sinatra %}
```ruby
```

```yaml
# config/karya.yml
defaults:
  backend: postgres
  backend_config:
    url: <%= ENV.fetch("DATABASE_URL") %>
  job_paths:
    - app/jobs
  boot_files: []

development: {}
test: {}
production: {}
```

```ruby

class ApplicationJob < Karya::Sinatra::Job
  abstract!
end

class BillingSyncJob < ApplicationJob
  queue_as :billing

  def perform(account_id, force: false)
  end
end

BillingSyncJob.perform_later(42, force: true)
```

```bash
bundle exec rake karya:work[billing]
bundle exec rake karya:runtime:inspect[billing]
```
{% endcapture %}

{% include tabs.html
  id="getting-started-complete"
  label="Getting started examples"
  count=4
  title1="Rails"
  content1=getting_started_rails
  title2="Hanami"
  content2=getting_started_hanami
  title3="Roda"
  content3=getting_started_roda
  title4="Sinatra"
  content4=getting_started_sinatra
%}

## Why `abstract!` Is On `ApplicationJob`

Mark the shared base class as `abstract!` so only concrete job classes can be
enqueued. That keeps queue names, handlers, and `perform` implementations
attached to real executable jobs instead of allowing work to be submitted
against a reusable base class.

It also prevents an easy footgun: accidentally calling
`ApplicationJob.perform_later` or enqueueing another shared base class. Marking
the base class abstract keeps that non-concrete path out of production instead
of letting it fail later when the worker tries to resolve executable job
behavior.

## How It Works In Practice

The enqueue call persists the canonical Karya job state immediately. The worker
command boots your app, discovers job classes under `app/jobs`, subscribes to
the requested queue, and starts executing matching work. The runtime inspect
command lets you confirm that the worker process for that queue set is alive
and discoverable.
