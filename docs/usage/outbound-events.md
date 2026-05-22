---
title: Outbound Events
parent: Usage
nav_parent: Usage
nav_order: 14
permalink: /usage/outbound-events/
---

# Outbound Events

Karya can normalize supported runtime events into CloudEvents-compatible
envelopes and deliver them through a configured dispatcher.

{% capture outbound_events_rails %}
```ruby
delivery_handler = lambda do |delivery|
  Net::HTTP.post(
    URI("https://hooks.example.com/karya"),
    delivery.body,
    delivery.headers
  )
end

dispatcher = Karya::OutboundEvents::Dispatcher.new(
  delivery_handler: delivery_handler,
  signer: Karya::OutboundEvents::WebhookSigner.new(
    secret: ENV.fetch("KARYA_WEBHOOK_SECRET")
  )
)

Karya.configure_outbound_event_dispatcher(dispatcher)
```
{% endcapture %}

{% capture outbound_events_hanami %}
```ruby
event = Karya::OutboundEvents::SchemaCatalog.build_event(
  event_name: "worker.job.started",
  payload: {
    reservation_token: "lease-1",
    job_id: "job-1",
    handler: "BillingSyncJob",
    queue: "billing",
    worker_id: "billing-worker"
  },
  occurred_at: Time.now.utc,
  event_id: "event-1"
)

dispatcher.call(event)
```
{% endcapture %}

{% capture outbound_events_roda %}
```ruby
dispatcher = Karya::OutboundEvents::Dispatcher.new(
  delivery_handler: ->(delivery) do
    Faraday.post(
      "https://hooks.example.com/karya",
      delivery.body,
      delivery.headers
    )
  end
)

Karya.configure_outbound_event_dispatcher(dispatcher)
```
{% endcapture %}

{% capture outbound_events_sinatra %}
```ruby
dispatcher = Karya::OutboundEvents::Dispatcher.new(
  delivery_handler: ->(delivery) do
    logger.info(
      event: "karya.outbound_delivery",
      headers: delivery.headers,
      body: delivery.body
    )
  end
)

Karya.configure_outbound_event_dispatcher(dispatcher)
```
{% endcapture %}

{% include tabs.html
  id="outbound-events-complete"
  label="Outbound event examples"
  count=4
  title1="Rails"
  content1=outbound_events_rails
  title2="Hanami"
  content2=outbound_events_hanami
  title3="Roda"
  content3=outbound_events_roda
  title4="Sinatra"
  content4=outbound_events_sinatra
%}

## How It Works In Practice

The dispatcher belongs in process boot so runtime events always have one
delivery path. Karya owns the event schema, envelope, and optional webhook
signature handling; your delivery handler owns transport concerns such as HTTP,
logging, queue fan-out, or forwarding into another event bus.
