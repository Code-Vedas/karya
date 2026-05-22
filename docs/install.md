---
title: Install
nav_order: 3
permalink: /install/
---

# Installation And Setup

Choose the package surface that matches your host application, then use the
framework-native install flow to generate config, job stubs, workflow stubs,
and backend migrations.

## Package Selection

- Plain Ruby services use `karya`
- Rails apps use `karya-rails`
- Hanami apps use `karya-hanami`
- Roda apps use `karya-roda`
- Sinatra apps use `karya-sinatra`

{% capture install_rails %}
```ruby
# Gemfile
gem "karya"
gem "karya-rails"
```

```bash
bundle install
bin/rails generate karya:install --backend=postgres
bin/rails db:migrate
```
{% endcapture %}

{% capture install_hanami %}
```ruby
# Gemfile
gem "karya"
gem "karya-hanami"
```

```bash
bundle install
bundle exec hanami karya:install --backend=postgres
```
{% endcapture %}

{% capture install_roda %}
```ruby
# Gemfile
gem "karya"
gem "karya-roda"
```

```bash
bundle install
bundle exec rake karya:install:all[postgres]
```
{% endcapture %}

{% capture install_sinatra %}
```ruby
# Gemfile
gem "karya"
gem "karya-sinatra"
```

```bash
bundle install
bundle exec rake karya:install:all[postgres]
```
{% endcapture %}

{% include tabs.html
  id="install-frameworks"
  label="Install by framework"
  count=4
  title1="Rails"
  content1=install_rails
  title2="Hanami"
  content2=install_hanami
  title3="Roda"
  content3=install_roda
  title4="Sinatra"
  content4=install_sinatra
%}

Use `--backend=mysql` or `--backend=sqlite` when that matches your app. Hanami,
Roda, and Sinatra should generate migrations for the backend path your app
actually uses.

## What The Install Flow Creates

Framework-native install commands create the same starter shape:

- framework config
- `app/jobs/application_job.rb`
- workflow source stub
- backend migrations

After install, continue with [Getting Started](/usage/getting-started/).
