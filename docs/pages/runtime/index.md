---
title: Runtime
nav_order: 4
permalink: /runtime/
has_children: true
has_toc: false
---

# Runtime

Karya’s runtime documentation covers the core execution model for jobs, queues,
workers, and operator-visible controls.

Everything else in Karya depends on the runtime being understandable,
inspectable, and operationally predictable.

## In This Section

- [Job Model](/runtime/job-model/): the executable unit, lifecycle, and state model
- [Workers](/runtime/workers/): reservation, execution, drain, and supervision behavior
- [Controls](/runtime/controls/): CLI, API, and operator control surfaces

## What This Section Covers

The runtime section is the source of truth for:

- canonical job and queue execution semantics
- canonical job lifecycle states and transition boundaries
- worker bootstrap and coordinated supervisor-managed execution flow
- graceful shutdown and drain behavior
- lifecycle controls that later reliability and workflow features build on

## About The Examples

The examples in this section are intentionally simple. They show how the
runtime is meant to feel without pretending every bootstrap or submission
detail is already frozen beyond the canonical lifecycle and control vocabulary.
