---
title: Reliability
nav_order: 5
permalink: /reliability/
has_children: true
has_toc: false
---

# Reliability

Karya treats routing and reliability as explicit product contracts. This section
covers the behaviors operators and developers need to reason about under load,
failure, and recovery.

Reliability is part of the product, not a hidden runtime detail. Teams should
be able to predict how Karya behaves when work piles up, retries spike, or
recovery paths are triggered.

## In This Section

- [Retries](/reliability/retries/)
- [Uniqueness](/reliability/uniqueness/)
- [Dead Letters](/reliability/dead-letters/)
- [Backpressure](/reliability/backpressure/)

## What This Section Covers

The reliability section documents:

- retry and backoff behavior
- idempotency and uniqueness expectations
- dead-letter isolation and governed recovery boundaries
- fairness, starvation prevention, rate limiting, and backpressure
- how routing decisions and worker subscriptions shape reliability outcomes

## About The Examples

The examples in this section focus on visible behavior: what operators see,
what developers can rely on, and how failure states become understandable.

Across this section:

- queues define where work is routed
- workers subscribe intentionally through queue and handler matching
- retries keep the same job instance moving through `failed` and
  `retry_pending`
- dead-letter handling begins after bounded retry or policy-based isolation
- recovery actions stay explicit instead of hiding behind implicit queue
  behavior
