---
title: Webhook Signatures
parent: Usage
nav_parent: Usage
nav_order: 15
permalink: /usage/webhook-signatures/
---

# Webhook Signatures

Karya signs outbound webhook deliveries with a stable HMAC contract and lets
receivers verify those deliveries with scheme, timestamp, and skew checks.

## Signature Contract

Every signed delivery includes:

- a signature scheme such as `v1`
- a timestamp header
- an HMAC digest over `timestamp.body`
- verification skew limits

{% capture webhook_rails %}
```ruby
dispatcher = Karya::OutboundEvents::Dispatcher.new(
  delivery_handler: ->(delivery) do
    Net::HTTP.post(
      URI("https://hooks.example.com/karya"),
      delivery.body,
      delivery.headers
    )
  end,
  signer: Karya::OutboundEvents::WebhookSigner.new(
    secret: ENV.fetch("KARYA_WEBHOOK_SECRET")
  )
)

Karya.configure_outbound_event_dispatcher(dispatcher)

post "/webhooks/karya" do
  verifier = Karya::OutboundEvents::WebhookVerifier.new(
    secret: ENV.fetch("KARYA_WEBHOOK_SECRET")
  )

  body = request.raw_post
  verifier.enforce_signature_validity!(
    body: body,
    headers: request.headers,
    now: Time.now.utc
  )

  head :accepted
end
```
{% endcapture %}

{% capture webhook_hanami %}
```ruby
Karya.configure_outbound_event_dispatcher(
  Karya::OutboundEvents::Dispatcher.new(
    delivery_handler: ->(delivery) do
      HTTP.headers(delivery.headers).post(
        "https://hooks.example.com/karya",
        body: delivery.body
      )
    end,
    signer: Karya::OutboundEvents::WebhookSigner.new(
      secret: ENV.fetch("KARYA_WEBHOOK_SECRET")
    )
  )
)

class Webhooks::Karya::Receive < Hanami::Action
  def handle(req, res)
    verifier = Karya::OutboundEvents::WebhookVerifier.new(
      secret: ENV.fetch("KARYA_WEBHOOK_SECRET")
    )

    verifier.enforce_signature_validity!(
      body: req.body.read,
      headers: req.env,
      now: Time.now.utc
    )

    res.status = 202
    res.body = "accepted"
  end
end
```
{% endcapture %}

{% capture webhook_roda %}
```ruby
Karya.configure_outbound_event_dispatcher(
  Karya::OutboundEvents::Dispatcher.new(
    delivery_handler: ->(delivery) do
      Faraday.post(
        "https://hooks.example.com/karya",
        delivery.body,
        delivery.headers
      )
    end,
    signer: Karya::OutboundEvents::WebhookSigner.new(
      secret: ENV.fetch("KARYA_WEBHOOK_SECRET")
    )
  )
)

route do |r|
  r.post "webhooks", "karya" do
    verifier = Karya::OutboundEvents::WebhookVerifier.new(
      secret: ENV.fetch("KARYA_WEBHOOK_SECRET")
    )

    verifier.enforce_signature_validity!(
      body: r.body.read,
      headers: request.env,
      now: Time.now.utc
    )

    response.status = 202
    "accepted"
  end
end
```
{% endcapture %}

{% capture webhook_sinatra %}
```ruby
Karya.configure_outbound_event_dispatcher(
  Karya::OutboundEvents::Dispatcher.new(
    delivery_handler: ->(delivery) do
      Faraday.post(
        "https://hooks.example.com/karya",
        delivery.body,
        delivery.headers
      )
    end,
    signer: Karya::OutboundEvents::WebhookSigner.new(
      secret: ENV.fetch("KARYA_WEBHOOK_SECRET")
    )
  )
)

post "/webhooks/karya" do
  verifier = Karya::OutboundEvents::WebhookVerifier.new(
    secret: ENV.fetch("KARYA_WEBHOOK_SECRET")
  )

  verifier.enforce_signature_validity!(
    body: request.body.read,
    headers: request.env,
    now: Time.now.utc
  )

  status 202
  "accepted"
end
```
{% endcapture %}

{% include tabs.html
  id="webhook-frameworks"
  label="Webhook signature flows"
  count=4
  title1="Rails"
  content1=webhook_rails
  title2="Hanami"
  content2=webhook_hanami
  title3="Roda"
  content3=webhook_roda
  title4="Sinatra"
  content4=webhook_sinatra
%}

## How It Works In Practice

Use one shared secret on both sides of the delivery boundary. Karya signs the
outbound payload before the HTTP delivery happens, and your receiving endpoint
verifies the raw body plus headers before it accepts the event. Reject missing
headers, invalid timestamps, unsupported signature schemes, and payloads
outside the allowed skew window.
