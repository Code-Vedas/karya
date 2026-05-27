---
title: Overview
nav_order: 2
permalink: /overview/
---

# Overview

Karya is a Ruby-first background job and workflow product for teams that want
one execution model across plain Ruby services, Rails apps, Hanami apps, Roda
hosts, and Sinatra hosts.

It gives you one product surface for:

- framework-native job classes
- supervisor-managed workers
- durable queue backends
- workflow orchestration
- operator runtime control
- outbound event delivery

## What Karya Owns

Karya handles:

- immediate job enqueue and execution
- queue reservation, leases, and recovery
- worker process and thread supervision
- workflow definition, execution, interaction, and recovery
- framework-native runtime inspection and control
- webhook signing and outbound event dispatch

Karya does not own recurring or cron-driven scheduling. Use Kaal when work must
run because of time rather than because application code enqueued it.

## Package Roles

- `karya`
  Core runtime, queue store contracts, workflows, CLI primitives, and shared
  backend vocabulary.
- `karya-rails`
  Rails-native jobs, workflows, worker commands, runtime control, install
  generator and tasks, and ActiveJob compatibility.
- `karya-hanami`
  Hanami-native jobs, workflows, worker commands, runtime control, and install
  command.
- `karya-roda`
  Roda-native jobs, workflows, worker tasks, runtime control, and install
  tasks.
- `karya-sinatra`
  Sinatra-native jobs, workflows, worker tasks, runtime control, and install
  tasks.

## Where Karya Fits

Use Karya when your application needs:

- framework-native background jobs with stable handler identity and queue routing
- one worker/runtime model across frameworks
- durable queueing with SQL or Redis backends
- workflow coordination with approvals, signals, rollbacks, and child flows
- operator-facing runtime control without custom control plumbing

Use Kaal alongside Karya when the trigger is time-based:

- nightly reconciliation
- hourly closeout
- recurring syncs
- cron-like reminders

See [Scheduling With Kaal](/scheduling-with-kaal/) for that boundary.

## Start Here

- [Install](/install/)
- [Usage](/usage/)
- [Scheduling With Kaal](/scheduling-with-kaal/)
- [FAQ](/faq/)
