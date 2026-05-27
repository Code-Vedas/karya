---
title: Worker Runtime
parent: Usage
nav_parent: Usage
nav_order: 3
permalink: /usage/worker-runtime/
---

# Worker Runtime

Karya workers run under a supervisor process. Framework worker commands boot
the app, discover framework-native job classes, subscribe to queues, and run
child worker processes with per-child thread pools.

{% capture worker_rails %}
```ruby
class BillingSyncJob < ApplicationJob
  queue_as :billing

  def perform(account_id, force: false)
  end
end
```

```bash
bin/rails karya:work billing critical \
  --name billing \
  --processes 2 \
  --threads 4 \
  --lease-duration 30 \
  --poll-interval 1
```
{% endcapture %}

{% capture worker_hanami %}
```ruby
class BillingSyncJob < ApplicationJob
  queue_as :billing

  def perform(account_id, force: false)
  end
end
```

```bash
bundle exec hanami karya:work billing critical \
  --name billing \
  --processes 2 \
  --threads 4 \
  --lease-duration 30 \
  --poll-interval 1
```
{% endcapture %}

{% capture worker_roda %}
```ruby
class BillingSyncJob < ApplicationJob
  queue_as :billing

  def perform(account_id, force: false)
  end
end
```

```bash
KARYA_WORKER_NAME=billing \
bundle exec rake karya:work[billing,critical]
```
{% endcapture %}

{% capture worker_sinatra %}
```ruby
class BillingSyncJob < ApplicationJob
  queue_as :billing

  def perform(account_id, force: false)
  end
end
```

```bash
KARYA_WORKER_NAME=billing \
bundle exec rake karya:work[billing,critical]
```
{% endcapture %}

{% include tabs.html
  id="worker-runtime-complete"
  label="Worker runtime examples"
  count=4
  title1="Rails"
  content1=worker_rails
  title2="Hanami"
  content2=worker_hanami
  title3="Roda"
  content3=worker_roda
  title4="Sinatra"
  content4=worker_sinatra
%}

## How It Works In Practice

Queue selection decides which jobs a worker may reserve. Job discovery decides
which classes the worker may execute. `--processes` controls child processes,
`--threads` controls per-child worker threads, and `--lease-duration` controls
reservation ownership windows. Worker identity is derived from the queue set,
plus `--name` or `KARYA_WORKER_NAME` when you run multiple runtimes for the
same queues.
