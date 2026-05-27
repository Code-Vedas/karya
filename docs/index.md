---
title: Karya
nav_order: 1
permalink: /
description: Karya is a Ruby-first background job and workflow product for Rails, Hanami, Roda, Sinatra, and plain Ruby hosts.
---

# Karya

Karya is a Ruby-first background job and workflow product for teams that want
one execution model across plain Ruby services, Rails apps, Hanami apps, Roda
hosts, and Sinatra hosts.

It combines a shared queueing and worker runtime, durable backend contracts,
workflow composition, operator runtime controls, framework integration helpers,
and outbound delivery primitives under one product vocabulary.

## Why Karya

Karya gives Ruby teams one job and workflow product instead of one queueing
story per framework. The same runtime model, backend contracts, workflow
semantics, and operator controls carry across plain Ruby services, Rails,
Hanami, Roda, and Sinatra, so teams do not have to relearn execution behavior
when apps span more than one host.

## What Karya Includes

- `karya` for core job submission, workers, workflows, CLI runtime control, and
  shared backend contracts
- `karya-rails` for Rails-native jobs, workflows, worker commands, runtime
  control, install tasks, and ActiveJob compatibility
- `karya-hanami` for Hanami-native jobs, workflows, worker commands, runtime
  control, and install commands
- `karya-roda` for Roda-native jobs, workflows, worker tasks, runtime control,
  and install tasks
- `karya-sinatra` for Sinatra-native jobs, workflows, worker tasks, runtime
  control, and install tasks

## Core Capability Summary

### Jobs And Queueing

Karya gives you framework-native job classes with explicit queue, handler, and
argument contracts underneath. The primary path is to declare a job class,
enqueue with `perform_later`, and let the runtime serialize arguments into the
canonical queued job state.

### Worker Runtime

The worker runtime is supervisor-managed. Framework worker commands boot the
host app, discover framework job classes, infer the runtime state file, and run
the shared supervisor with queue-specific process and thread settings.

### Backends And Reliability

Karya defines one durability contract across in-memory, SQL, and Redis-backed
queue stores. Reliability controls include retry policies, idempotency,
uniqueness, lease recovery, backpressure scopes, circuit-breaker policies, and
reservation fairness.

### Workflows

Karya workflows use framework-native Ruby DSLs for step graphs, dependencies,
approvals, signals, child workflows, rollback, replay, and workflow history.
Concrete jobs remain the executable units while workflow metadata gates when
those jobs may run.

### Runtime And Operator Surfaces

Framework integrations expose health, readiness, operator payloads, runtime
probe payloads, operator authorization composition, and framework-native
runtime inspection, drain, and force-stop commands.

### Outbound Events

Karya can normalize supported runtime events into CloudEvents-style envelopes
and sign deliveries for webhook consumers with a stable HMAC contract.

## Framework Quick Start

Each framework package gives you a first-class entrypoint into the same Karya
runtime model.

Examples use each host's native command surface: `bin/rails` for Rails,
`bundle exec hanami` for Hanami, and `bundle exec rake` for Roda and Sinatra.

{% capture overview_rails %}
```ruby
# Gemfile
gem 'karya'
gem 'karya-rails'
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
bin/rails karya:work billing \
  --processes 1 \
  --threads 4
```
{% endcapture %}

{% capture overview_hanami %}
```ruby
# Gemfile
gem 'karya'
gem 'karya-hanami'
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
bundle exec hanami karya:work billing \
  --processes 1 \
  --threads 4
```
{% endcapture %}

{% capture overview_roda %}
```ruby
# Gemfile
gem 'karya'
gem 'karya-roda'
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
bundle exec rake karya:work[billing] \
  --processes 1 \
  --threads 4
```
{% endcapture %}

{% capture overview_sinatra %}
```ruby
# Gemfile
gem 'karya'
gem 'karya-sinatra'
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
bundle exec rake karya:work[billing] \
  --processes 1 \
  --threads 4
```
{% endcapture %}

{% include tabs.html
  id="overview-frameworks"
  label="Framework quick starts"
  count=4
  title1="Rails"
  content1=overview_rails
  title2="Hanami"
  content2=overview_hanami
  title3="Roda"
  content3=overview_roda
  title4="Sinatra"
  content4=overview_sinatra
%}

## Start Here

- [Overview](/overview/)
- [Installation And Setup](/install/)
- [Usage](/usage/)
- [Scheduling With Kaal](/scheduling-with-kaal/)
- [FAQ](/faq/)
- [Professional Support](/support/)
- [Contribute](/contribute/)
