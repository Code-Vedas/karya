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
- [Examples](/workflows/examples/)

## What This Section Covers

The workflows section documents composition, state transitions, compensation,
inspection, live interaction, and safe evolution semantics.

## About The Examples

The examples in this section use the Ruby workflow composition DSL, concrete
queue-store runtime behavior, workflow snapshots, rollback metadata, and
operator recovery controls together.

They show workflow behavior as a product surface: how developers model a run,
how workers reserve ready steps, and how operators inspect and recover the
workflow without reaching into internal queue-store state.
