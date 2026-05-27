---
title: Runtime Control CLI
parent: Usage
nav_parent: Usage
nav_order: 9
permalink: /usage/runtime-control-cli/
---

# Runtime Control

Framework-native runtime control commands inspect a running worker, begin drain,
or force-stop it. The framework command resolves the worker identity from the
queue set, so application teams do not need to manage raw state-file paths.

Use `drain` for normal deploys and rolling restarts. It lets the worker stop
accepting new work while the current job finishes cleanly. Reserve
`force-stop` for emergencies or last-resort shutdowns when you are willing to
interrupt a running job.

{% capture runtime_cli_rails %}
```bash
bin/rails karya:work billing critical --name billing
bin/rails karya:runtime inspect billing critical --name billing
bin/rails karya:runtime drain billing critical --name billing
bin/rails karya:runtime force-stop billing critical --name billing
```
{% endcapture %}

{% capture runtime_cli_hanami %}
```bash
bundle exec hanami karya:work billing critical --name billing
bundle exec hanami karya:runtime inspect billing critical --name billing
bundle exec hanami karya:runtime drain billing critical --name billing
bundle exec hanami karya:runtime force-stop billing critical --name billing
```
{% endcapture %}

{% capture runtime_cli_roda %}
```bash
KARYA_WORKER_NAME=billing bundle exec rake karya:work[billing,critical]
KARYA_WORKER_NAME=billing bundle exec rake karya:runtime:inspect[billing,critical]
KARYA_WORKER_NAME=billing bundle exec rake karya:runtime:drain[billing,critical]
KARYA_WORKER_NAME=billing bundle exec rake karya:runtime:force_stop[billing,critical]
```
{% endcapture %}

{% capture runtime_cli_sinatra %}
```bash
KARYA_WORKER_NAME=billing bundle exec rake karya:work[billing,critical]
KARYA_WORKER_NAME=billing bundle exec rake karya:runtime:inspect[billing,critical]
KARYA_WORKER_NAME=billing bundle exec rake karya:runtime:drain[billing,critical]
KARYA_WORKER_NAME=billing bundle exec rake karya:runtime:force_stop[billing,critical]
```
{% endcapture %}

{% include tabs.html
  id="runtime-control-complete"
  label="Runtime control examples"
  count=4
  title1="Rails"
  content1=runtime_cli_rails
  title2="Hanami"
  content2=runtime_cli_hanami
  title3="Roda"
  content3=runtime_cli_roda
  title4="Sinatra"
  content4=runtime_cli_sinatra
%}

## How It Works In Practice

Start the worker for the queue set first, then use the matching inspect, drain,
or force-stop command against that same queue set and logical worker name. The
framework wrapper infers the runtime state path, keeps control requests routed
through the supervisor control socket, and avoids exposing low-level
`--state-file` handling as the normal application path.

Operator and dashboard routes stay denied until the app configures an explicit
operator authorizer. Runtime control still works locally through the framework
commands because they target the inferred supervisor state and control socket
directly.
