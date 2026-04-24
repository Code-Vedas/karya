---
title: Workflows
nav_order: 6
permalink: /workflows/
has_children: true
has_toc: false
---

# Workflows

Karya includes durable workflow orchestration for teams that need replayable,
inspectable, and evolvable long-running execution.

The goal is not just to chain jobs together. It is to give complex execution a
clear lifecycle, recovery model, and operator story.

## In This Section

- [Basics](/workflows/basics/)
- [Replay](/workflows/replay/)
- [Signals](/workflows/signals/)
- [Child Workflows](/workflows/child-workflows/)
- [Versioning](/workflows/versioning/)

## What This Section Covers

The workflows section documents composition, state transitions, compensation,
inspection, live interaction, and safe evolution semantics.

## About The Examples

The examples in this section align with the Ruby workflow composition DSL that
builds normalized immutable workflow definitions in `core/karya`.

Later workflow tickets extend execution, recovery, interaction, and evolution
semantics on top of that foundation, so the examples here focus on composition
shape and operator meaning rather than every later runtime detail.
