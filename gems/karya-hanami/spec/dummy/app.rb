# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'json'
require 'hanami'
require 'karya/hanami'
require 'kaal/hanami'

class ExampleHeartbeatJob
  def self.perform(*); end
end

def karya_hanami_kaal_app
  Class.new do
    config = Struct.new(:root, :env, :middleware).new(File.expand_path(__dir__), :test, nil)
    define_singleton_method(:config) { config }
  end
end

Kaal::Hanami.register!(karya_hanami_kaal_app, namespace: 'karya-hanami-dummy')

def karya_hanami_dummy_app
  proc do |env|
    authorize_operator_request = lambda do
      next nil if Karya::Hanami.operator_access_authorized?(env)

      [
        403,
        { 'content-type' => 'application/json; charset=utf-8' },
        [JSON.generate('error' => 'forbidden')]
      ]
    end

    case env['PATH_INFO']
    when '/karya/runtime-probe' then json_response(Karya::Hanami.runtime_probe_payload)
    when '/kaal/probe' then kaal_probe_response
    when '/karya/health' then json_response(Karya::Hanami.health_payload)
    when '/karya/readiness' then json_response(Karya::Hanami.readiness_payload)
    when '/karya/operator-probe'
      denied_response = authorize_operator_request.call
      next denied_response if denied_response

      json_response(Karya::Hanami.operator_payload)
    when '/karya'
      denied_response = authorize_operator_request.call
      next denied_response if denied_response

      html_response(Karya::Hanami.render_dashboard_page)
    else
      [404, { 'content-type' => 'text/plain' }, ['not found']]
    end
  end
end

def kaal_probe_response
  json_response(
    'backend' => Kaal.configuration.backend.class.name,
    'registered' => Kaal.registered?(key: 'hanami:heartbeat')
  )
end

def json_response(payload)
  [200, { 'content-type' => 'application/json; charset=utf-8' }, [JSON.generate(payload)]]
end

def html_response(body)
  [200, { 'content-type' => 'text/html; charset=utf-8' }, [body]]
end
