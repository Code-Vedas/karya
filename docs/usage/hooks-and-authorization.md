---
title: Hooks And Authorization
parent: Usage
nav_parent: Usage
nav_order: 16
permalink: /usage/hooks-and-authorization/
---

# Hooks And Authorization

Karya exposes process-wide hooks for runtime events and framework-local
operator authorization surfaces for host policy checks.

{% capture hooks_rails %}
```ruby
Karya::Hooks.register(:worker_started, lambda do |payload|
  Rails.logger.info(event: "karya.worker_started", payload:)
end)

Karya::Hooks.register(:operator_authorization, lambda do |payload|
  payload.fetch("authorized") &&
    payload.fetch("request_context").fetch(:role) == "operator"
end)

Karya::Rails.configure_operator_authorizer(
  lambda do |request_context|
    request_context.fetch(:role) == "operator"
  end
)

authorized = Karya::Rails.operator_access_authorized?(
  { role: "operator", tenant: "acme" }
)
```
{% endcapture %}

{% capture hooks_hanami %}
```ruby
Karya::Hooks.register(:worker_started, ->(payload) { logger.info(payload) })
Karya::Hooks.register(:worker_stopped, ->(payload) { logger.info(payload) })

Karya::Hanami.configure_operator_authorizer(
  lambda do |request_context|
    request_context.fetch(:tenant) == "acme" &&
      request_context.fetch(:role) == "operator"
  end
)

authorized = Karya::Hanami.operator_access_authorized?(
  { role: "operator", tenant: "acme" }
)
```
{% endcapture %}

{% capture hooks_roda %}
```ruby
Karya::Hooks.register(:worker_started, ->(payload) { logger.info(payload) })

Karya::Roda.configure_operator_authorizer(
  lambda do |request_context|
    request_context.fetch(:role) == "operator"
  end
)

authorized = Karya::Roda.operator_access_authorized?(
  { role: "operator", tenant: "acme" }
)
```
{% endcapture %}

{% capture hooks_sinatra %}
```ruby
Karya::Hooks.register(:worker_started, ->(payload) { logger.info(payload) })
Karya::Hooks.register(:active_job_execute, ->(payload) { logger.info(payload) })

Karya::Sinatra.configure_operator_authorizer(
  lambda do |request_context|
    request_context.fetch(:role) == "operator"
  end
)

authorized = Karya::Sinatra.operator_access_authorized?(
  { role: "operator", tenant: "acme" }
)
```
{% endcapture %}

{% include tabs.html
  id="hooks-complete"
  label="Hooks and authorization examples"
  count=4
  title1="Rails"
  content1=hooks_rails
  title2="Hanami"
  content2=hooks_hanami
  title3="Roda"
  content3=hooks_roda
  title4="Sinatra"
  content4=hooks_sinatra
%}

## How It Works In Practice

Use framework-local operator authorizers for route and dashboard access policy.
Use hooks for cross-cutting audit, instrumentation, or policy shaping that
should observe runtime events without changing the framework-facing surface.
