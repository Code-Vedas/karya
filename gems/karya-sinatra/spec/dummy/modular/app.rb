# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'sinatra/base'
require 'karya/sinatra'
require 'kaal/sinatra'
require 'json'

class ExampleHeartbeatJob
  def self.perform(*); end
end

class KaryaSinatraDummyApp < Sinatra::Base
  set :root, File.expand_path(__dir__)

  register Kaal::Sinatra::Extension
  kaal namespace: 'karya-sinatra-dummy',
       start_scheduler: false

  helpers do
    def authorize_operator_request!
      return if Karya::Sinatra.operator_access_authorized?(request)

      halt 403, { 'content-type' => 'application/json; charset=utf-8' }, JSON.generate('error' => 'forbidden')
    end
  end

  get '/karya' do
    authorize_operator_request!
    content_type 'text/html'
    Karya::Sinatra.render_dashboard_page
  end

  get '/karya/runtime-probe' do
    content_type 'application/json'
    JSON.generate(Karya::Sinatra.runtime_probe_payload)
  end

  get '/kaal/probe' do
    content_type 'application/json'
    JSON.generate(
      'backend' => Kaal.configuration.backend.class.name,
      'registered' => Kaal.registered?(key: 'sinatra:heartbeat')
    )
  end

  get '/karya/health' do
    content_type 'application/json'
    JSON.generate(Karya::Sinatra.health_payload)
  end

  get '/karya/readiness' do
    content_type 'application/json'
    JSON.generate(Karya::Sinatra.readiness_payload)
  end

  get '/karya/operator-probe' do
    authorize_operator_request!
    content_type 'application/json'
    JSON.generate(Karya::Sinatra.operator_payload)
  end
end
