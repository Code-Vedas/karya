---
title: FAQ
nav_order: 101
permalink: /faq/
---

# FAQ

## Do I use Karya or Kaal for scheduled work?

Use Karya for immediate enqueue, workers, and workflows. Use Kaal for recurring
or scheduled dispatch. See [Scheduling With Kaal](/scheduling-with-kaal/).

## Do I need plain `karya` plus a framework gem?

Yes. Framework packages build on the shared `karya` runtime and expose the
framework-native job, workflow, install, and runtime surfaces.

## Which backend should I use?

- `InMemory` for local development and examples
- `Postgres` for durable shared SQL-backed workers
- `MySQL` for durable shared SQL-backed workers
- `SQLite` for simpler local or constrained deployments
- `Redis` when the queue store should live in Redis

See [Backends And Durability](/usage/backends-and-durability/).

## How do I inspect a running worker?

Use the framework runtime command for the queue set you started:

- Rails: `bin/rails karya:runtime inspect billing`
- Hanami: `bundle exec hanami karya:runtime inspect billing`
- Roda: `bundle exec rake karya:runtime:inspect[billing]`
- Sinatra: `bundle exec rake karya:runtime:inspect[billing]`

If the app also exposes dashboard or operator HTTP routes, configure an
operator authorizer explicitly. Those routes are deny-by-default.

## Why are my jobs not loading?

Check:

- job classes live under `app/jobs`
- jobs inherit from `Karya::<Framework>::Job`
- the worker command is running for the queue you enqueued to
- the framework app booted with the same code and config you expect

## Where should job classes live?

Use `app/jobs` for framework apps. That keeps worker discovery predictable and
matches the framework-native install flow.

## What should stay stable in workflow definitions?

Keep these stable unless you are doing an intentional versioned workflow
change:

- workflow id
- workflow family and version boundaries
- step ids
- dependency intent
- job class meaning

## When do I use ActiveJob versus `Karya::Rails::Job`?

Use `Karya::Rails::Job` as the primary Karya-native path. Use the ActiveJob
bridge only when a Rails app explicitly wants ActiveJob semantics or
compatibility.

The ActiveJob bridge also submits immediately when the app enqueues a job. If
the app needs dispatch to wait for its own transaction commit, enqueue from the
commit boundary the app controls.

## What does runtime control act on if I do not pass a state file?

Framework commands infer the worker identity and the runtime state path from
the queue set, plus `--name` or `KARYA_WORKER_NAME` when you override the
logical worker name.

## Can I use Karya without a framework?

Yes. The core `karya` gem supports plain Ruby usage, but the primary docs site
is optimized for framework app teams.
