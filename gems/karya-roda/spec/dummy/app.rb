# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'roda'
require 'karya/roda'
require 'kaal/roda'
require 'json'

class ExampleHeartbeatJob
  def self.perform(*); end
end

class KaryaRodaDummyApp < Roda
  opts[:root] = File.expand_path(__dir__)
  opts[:environment] = ENV.fetch('RACK_ENV', 'test')

  plugin :kaal

  kaal namespace: 'karya-roda-dummy',
       start_scheduler: false

  route do |r|
    operator_access_authorized = lambda do
      next true if Karya::Roda.operator_access_authorized?(r)

      response.status = 403
      response['content-type'] = 'application/json; charset=utf-8'
      response.write(JSON.generate('error' => 'forbidden'))
      false
    end

    r.is 'karya', 'runtime-probe' do
      response['content-type'] = 'application/json; charset=utf-8'
      JSON.generate(Karya::Roda.runtime_probe_payload)
    end

    r.is 'kaal', 'probe' do
      response['content-type'] = 'application/json; charset=utf-8'
      JSON.generate(
        'backend' => Kaal.configuration.backend.class.name,
        'registered' => Kaal.registered?(key: 'roda:heartbeat')
      )
    end

    r.is 'karya', 'health' do
      response['content-type'] = 'application/json; charset=utf-8'
      JSON.generate(Karya::Roda.health_payload)
    end

    r.is 'karya', 'readiness' do
      response['content-type'] = 'application/json; charset=utf-8'
      JSON.generate(Karya::Roda.readiness_payload)
    end

    r.is 'karya', 'operator-probe' do
      next unless operator_access_authorized.call

      response['content-type'] = 'application/json; charset=utf-8'
      JSON.generate(Karya::Roda.operator_payload)
    end

    r.is 'karya' do
      next unless operator_access_authorized.call

      response['content-type'] = 'text/html; charset=utf-8'
      Karya::Roda.render_dashboard_page
    end
  end
end
