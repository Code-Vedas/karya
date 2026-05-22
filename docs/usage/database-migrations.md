---
title: Database Migrations
parent: Usage
nav_parent: Usage
nav_order: 7
permalink: /usage/database-migrations/
---

# Database Migrations

Framework-native install commands are the main migration path. They generate
the framework config, `ApplicationJob`, workflow source stub, and the backend
migrations that match your selected queue-store backend.

{% capture migrations_rails %}
```bash
bin/rails generate karya:install --backend=postgres
bin/rails db:migrate
bin/rake karya:install:migrations[postgres]
```
{% endcapture %}

{% capture migrations_hanami %}
```bash
bundle exec hanami karya:install --backend=postgres
```
{% endcapture %}

{% capture migrations_roda %}
```bash
bundle exec rake karya:install:all[mysql]
bundle exec rake karya:install:migrations[mysql]
```
{% endcapture %}

{% capture migrations_sinatra %}
```bash
bundle exec rake karya:install:all[sqlite]
bundle exec rake karya:install:migrations[sqlite]
```
{% endcapture %}

{% include tabs.html
  id="migrations-complete"
  label="Migration installer examples"
  count=4
  title1="Rails"
  content1=migrations_rails
  title2="Hanami"
  content2=migrations_hanami
  title3="Roda"
  content3=migrations_roda
  title4="Sinatra"
  content4=migrations_sinatra
%}

## How It Works In Practice

Use the install command that matches the backend you configure through
`Karya::<Framework>.configure`. Treat raw migration installer methods as
internal support plumbing for the framework install surface, not as the normal
application path.
