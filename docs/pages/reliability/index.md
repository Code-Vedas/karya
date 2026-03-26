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
- poison-job and dead-letter recovery flows
- fairness, starvation prevention, rate limiting, and backpressure

## About The Examples

The examples in this section focus on visible behavior: what operators see,
what developers can rely on, and how failure states become understandable.
