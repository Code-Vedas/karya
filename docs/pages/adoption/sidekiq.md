---
title: Sidekiq
parent: Adoption
nav_order: 1
permalink: /adoption/sidekiq/
---

# Sidekiq

Sidekiq teams often start by mapping queues, workers, retries, and operator
workflows into the Karya model.

## Guidance

- map queues and workers to the Karya runtime model
- map retries, uniqueness, dead-letter isolation, and governed recovery to the
  reliability model
- treat dashboard adoption as an operator workflow change, not only a backend
  swap

## Common Scenarios

### Moving A Familiar Queue Model

Sidekiq adoption often starts with concept mapping:

```text
current_system: sidekiq
current_queue: billing
target_runtime: karya
target_queue: billing
migration_focus: retries, isolation, uniqueness, operator workflows
```

The goal is to preserve familiar operational concepts while moving into the
broader Karya runtime and operator model.

## Related Concepts

- [Retries](/reliability/retries/): retry behavior is usually the first
  migration concern
- [Uniqueness](/reliability/uniqueness/): duplicate suppression often needs
  explicit review
- [Cutover And Rollback](/adoption/cutover-rollback/): migration planning continues into
  rollout
