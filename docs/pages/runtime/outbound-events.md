---
title: Outbound Events
nav_order: 4
parent: Runtime
permalink: /runtime/outbound-events/
---

# Outbound Events

Karya exposes outbound runtime events as a versioned external contract rather
than an ad hoc instrumentation stream.

These events are the standards-facing path for external consumers that need to
observe runtime execution, react to workflow-safe operator signals, or verify
deliveries through signed webhook conventions.

## Contract Shape

Outbound events use a CloudEvents-compatible JSON envelope with:

- `specversion`
- `id`
- `source`
- `type`
- `time`
- `subject` when the event naturally targets one job or child process
- `datacontenttype`
- `dataschema`
- `karyaschemaversion`
- `data`

Karya keeps the event envelope stable while versioning payload schemas
explicitly through `karyaschemaversion` and the schema URI carried in
`dataschema`.

## Supported Event Families

The runtime contract includes versioned outbound events for Karya-owned runtime
surfaces such as:

- worker job reservation, start, success, failure, and release
- worker orphan recovery reporting
- supervisor child spawn activity
- supervisor shutdown signal forwarding

New event families can be added over time, but supported families do not drift
silently. A consumer can treat the event `type` and schema version as the
compatibility boundary.

## Version Evolution

Outbound event schemas evolve intentionally:

- additive changes stay within the same schema version when existing consumers
  remain valid
- breaking payload changes move to a new schema version
- the event envelope stays CloudEvents-compatible even when payload versions
  advance

Karya does not rely on an implicit “latest payload” contract for external event
consumers.

## Webhook Signing

Karya signs webhook-style deliveries over the canonical serialized event body.

The signing convention uses:

- `Karya-Webhook-Timestamp`: epoch seconds used in the signature base string
- `Karya-Webhook-Signature`: versioned digest metadata such as `v1=<digest>`

The signature input is the exact base string `"#{timestamp}.#{body}"`: the
timestamp header value, then a literal `.` delimiter, then the canonical body
bytes. Consumers verify that exact byte sequence with the shared secret, reject
tampered payloads, and enforce a bounded timestamp window to reduce replay
exposure.

Karya computes the digest with `HMAC-SHA256` over that exact byte sequence and
encodes the digest as lowercase hexadecimal in `Karya-Webhook-Signature`.
The `v1` prefix is the signing scheme and version label for the delivery
contract; it is not the hash algorithm name.

## Enabling Delivery

Karya treats outbound delivery as an explicit runtime collaborator, not as an
always-on side effect.

You can supply an outbound dispatcher either:

- process-wide through `Karya.configure_outbound_event_dispatcher(...)`
- per runtime through `outbound_event_dispatcher:` on worker and
  worker-supervisor runtime construction

Process-wide configuration is the default only for runtimes that do not receive
an explicit dispatcher. Multi-runtime hosts should prefer explicit
`outbound_event_dispatcher:` injection so one runtime’s delivery policy does
not leak into another runtime by accident.

The dispatcher contract is versioned outbound delivery, not raw mutable
instrumentation. Unsupported runtime events are ignored rather than becoming
part of the external event contract automatically.

## Verifying Deliveries

Consumers verify webhook deliveries by:

1. reading `Karya-Webhook-Timestamp`
2. reading `Karya-Webhook-Signature`
3. rebuilding the exact base string `"#{timestamp}.#{body}"`
4. computing the expected digest with the shared secret
5. rejecting requests whose timestamp falls outside the allowed skew window

`Karya::OutboundEvents::WebhookVerifier` enforces a default maximum skew window
of `300` seconds. Hosts that need a different replay window can provide an
explicit `max_skew_seconds:` value, but the verifier still expects the exact
timestamp header bytes to match the signed base string.

## Related Concepts

- [Observability](/observability/): traces, logs, metrics, and outbound event
  delivery form one external monitoring story
- [Runtime](/runtime/): outbound events describe runtime execution, not a
  separate delivery subsystem
- [Operator](/operator/): operator actions and drilldowns should align with the
  events external systems observe
