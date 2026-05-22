---
title: Backends And Durability
parent: Usage
nav_parent: Usage
nav_order: 4
permalink: /usage/backends-and-durability/
---

# Backends And Durability

Karya uses one queue-store durability contract across in-memory, SQL, and
Redis-backed backends. Each backend defines its storage model and coordination
scope.

## Backend Choices

- `Karya::Backend::InMemory` for local development and examples
- `Karya::Backend::Postgres` for durable shared storage
- `Karya::Backend::MySQL` for durable shared storage
- `Karya::Backend::SQLite` for file-backed local or constrained deployments
- `Karya::Backend::Redis` for Redis-backed queue state

## How To Choose

For a regular production workload under roughly `5k jobs/sec`, the default
recommendation is to use the same production database your application already
operates, as long as your team is comfortable sharing that database with Karya
job tables. That usually keeps the architecture simpler and avoids the cost of
running another datastore just for background work.

Use Postgres or MySQL when durability and operational simplicity matter more
than absolute enqueue throughput. Use Redis when you want higher sustained
throughput, tighter workload isolation, or a separate queue datastore from the
start. Use SQLite for local environments, single-host deployments, and
constrained installations where a file-backed durable queue is the right trade.

Treat the throughput numbers here as selection guidance, not hard support
limits. Final backend choice should still reflect workload shape, failure
isolation requirements, and your team’s operating model.

{% capture backends_rails %}
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

```bash
bin/rails karya:work billing
```
{% endcapture %}

{% capture backends_hanami %}
```yaml
# config/karya.yml
defaults:
  backend: mysql
  backend_config:
    url: <%= ENV.fetch("DATABASE_URL") %>
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

{% capture backends_roda %}
```yaml
# config/karya.yml
defaults:
  backend: redis
  backend_config:
    url: <%= ENV.fetch("REDIS_URL") %>
  job_paths:
    - app/jobs
  boot_files: []

development: {}
test: {}
production: {}
```

```bash
bundle exec rake karya:work[billing]
```
{% endcapture %}

{% capture backends_sinatra %}
```yaml
# config/karya.yml
defaults:
  backend: sqlite
  backend_config:
    url: <%= ENV.fetch("DATABASE_URL") %>
  job_paths:
    - app/jobs
  boot_files: []

development: {}
test: {}
production: {}
```

```bash
bundle exec rake karya:work[billing]
```
{% endcapture %}

{% include tabs.html
  id="backends-complete"
  label="Backend setup examples"
  count=4
  title1="Rails"
  content1=backends_rails
  title2="Hanami"
  content2=backends_hanami
  title3="Roda"
  content3=backends_roda
  title4="Sinatra"
  content4=backends_sinatra
%}

## How It Works In Practice

An enqueue succeeds only after the queued state is durable in the configured
backend. Reservation, execution start, completion, failure, and recovery all
operate on persisted queue state rather than worker memory. Use a shared durable
backend for multi-process or multi-host workers, and treat `InMemory` as
development-only bootstrap behavior.
