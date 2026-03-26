---
title: Frameworks
nav_order: 8
permalink: /frameworks/
has_children: true
has_toc: false
---

# Frameworks

Karya documents plain Ruby, Rails, Sinatra, Roda, and Hanami as first-class
entrypoints. ActiveJob is a first-class compatibility path.

Each host keeps its own integration style, but the runtime, dashboard,
scheduling, and operator model stay recognizably Karya.

## In This Section

- [Plain Ruby](/frameworks/plain-ruby/)
- [Rails](/frameworks/rails/)
- [Sinatra](/frameworks/sinatra/)
- [Roda](/frameworks/roda/)
- [Hanami](/frameworks/hanami/)
- [ActiveJob](/frameworks/activejob/)

## Framework Parity

All supported hosts share:

- the same Karya runtime model
- the same Kaal-backed scheduling story
- the same operator vocabulary
- the same optional dashboard addon, internal API model, and packaged asset
  contract when the addon is included

## About The Examples

The examples in this section show how Karya fits into each host. They are here
to make composition obvious without turning the docs into a speculative contract
reference.
