---
title: Framework Host Integration
parent: Usage
nav_parent: Usage
nav_order: 6
permalink: /usage/framework-host-integration/
---

# Framework Host Integration

Framework packages expose host-local helpers for health, readiness, operator
payloads, mount paths, dashboard rendering, and operator authorization.
Operator and dashboard surfaces stay closed until the app configures an
authorizer explicitly, while health and readiness remain safe to publish as
standard host checks.

{% capture framework_host_rails %}
```ruby
Karya::Rails.configure_operator_authorizer(
  lambda do |request_context|
    request_context.fetch(:role) == "operator"
  end
)

health = Karya::Rails.health_payload
readiness = Karya::Rails.readiness_payload
operator = Karya::Rails.operator_payload(mount_path: "/ops/karya")
probe = Karya::Rails.runtime_probe_payload(mount_path: "/ops/karya")

html = Karya::Rails.render_dashboard_page(
  mount_path: "/ops/karya",
  title: "Karya Operations"
)
```
{% endcapture %}

{% capture framework_host_hanami %}
```ruby
Karya::Hanami.configure_operator_authorizer(
  lambda do |request_context|
    request_context.fetch(:role) == "operator"
  end
)

health = Karya::Hanami.health_payload
readiness = Karya::Hanami.readiness_payload
operator = Karya::Hanami.operator_payload(prefix: "/ops")
probe = Karya::Hanami.runtime_probe_payload(prefix: "/ops")

html = Karya::Hanami.render_dashboard_page(prefix: "/ops")
```
{% endcapture %}

{% capture framework_host_roda %}
```ruby
Karya::Roda.configure_operator_authorizer(
  lambda do |request_context|
    request_context.fetch(:role) == "operator"
  end
)

health = Karya::Roda.health_payload
readiness = Karya::Roda.readiness_payload
operator = Karya::Roda.operator_payload(scope: "/ops")
probe = Karya::Roda.runtime_probe_payload(scope: "/ops")

html = Karya::Roda.render_dashboard_page(scope: "/ops")
```
{% endcapture %}

{% capture framework_host_sinatra %}
```ruby
Karya::Sinatra.configure_operator_authorizer(
  lambda do |request_context|
    request_context.fetch(:role) == "operator"
  end
)

health = Karya::Sinatra.health_payload
readiness = Karya::Sinatra.readiness_payload
operator = Karya::Sinatra.operator_payload(scope: "/ops")
probe = Karya::Sinatra.runtime_probe_payload(scope: "/ops")

html = Karya::Sinatra.render_dashboard_page(scope: "/ops")
```
{% endcapture %}

{% include tabs.html
  id="framework-host-complete"
  label="Framework host integration examples"
  count=4
  title1="Rails"
  content1=framework_host_rails
  title2="Hanami"
  content2=framework_host_hanami
  title3="Roda"
  content3=framework_host_roda
  title4="Sinatra"
  content4=framework_host_sinatra
%}

## How It Works In Practice

Use the health and readiness payloads for host health endpoints, the operator
payload for an operations surface, and `render_dashboard_page` when the app
serves the dashboard document itself. Frameworks differ in whether they call
that path a mount path, prefix, or scope, but the product surface is the same.
These helpers reuse the shared host runtime inside the app process, so repeated
health and operator requests do not rebuild backend connections on every call.
