# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'
require 'json'

RSpec.describe Karya::Rails, :dashboard_manifest_fixture, :integration do
  if ENV['E2E'] == '1'
    require 'rails_helper'
    require 'rack/test'
    include Rack::Test::Methods
  end

  around do |example|
    skip 'set KARYA_REDIS_URL or REDIS_URL for Redis e2e coverage' unless ENV['KARYA_REDIS_URL'] || ENV['REDIS_URL']

    original_framework_authorizer = described_class.operator_authorizer
    original_global_authorizer = Karya.operator_authorizer if Karya.instance_variable_defined?(:@operator_authorizer)
    described_class.configure_operator_authorizer(->(_request_context) { true })
    self.current_app_root = Rails.root.to_s
    with_redis_backend(namespace: 'rails_redis_e2e') do
      Kaal.reset_configuration!
      Kaal.load_config_file!(
        runtime_context: Kaal::Runtime::RuntimeContext.new(root_path: Rails.root, environment_name: Rails.env)
      )
      example.run
    end
  ensure
    Karya.configure_operator_authorizer(original_global_authorizer)
    described_class.configure_operator_authorizer(original_framework_authorizer)
    self.current_app_root = nil
  end

  it 'mounts the dashboard engine and serves the packaged document' do
    get '/karya'

    expect(last_response).to have_http_status(:ok)
    expect_dashboard_document(last_response.body, mount_path: '/karya', title: 'Karya Dashboard')
  end

  it 'uses the configured Redis backend through the mounted engine' do
    get '/karya/runtime-probe'

    expect(last_response).to have_http_status(:ok)
    payload = JSON.parse(last_response.body)
    expect(payload.fetch('backend')).to eq('redis')
    expect(payload.fetch('job_id')).to start_with('rails-probe-')
    expect(payload.fetch('mount_path')).to eq('/karya')
  end

  it 'exposes health, readiness, and operator payloads through the mounted engine' do
    get '/karya/health'
    expect(JSON.parse(last_response.body)).to include('status' => 'ok', 'backend' => 'redis')

    get '/karya/readiness'
    expect(JSON.parse(last_response.body)).to include('status' => 'ready', 'backend' => 'redis')

    get '/karya/operator'
    expect(JSON.parse(last_response.body)).to include('backend' => 'redis', 'mount_path' => '/karya')
  end

  it 'enqueues ActiveJob payloads through the Rails compatibility path' do
    get '/karya/active-job-probe'
    expect(JSON.parse(last_response.body).fetch('adapter')).to eq('Karya::ActiveJob::QueueAdapter')

    runtime = Karya::FrameworkRuntime.build(backend_class: Karya.backend_class, backend_options: Karya.backend_options)
    runtime.start
    reservation = runtime.queue_store.reserve(queue: 'dashboard', worker_id: 'rails-active-job-worker', lease_duration: 60, now: Time.now.utc + 1)
    running_job = runtime.queue_store.start_execution(reservation_token: reservation.token, now: Time.now.utc + 2)

    expect do
      described_class.active_job_handler.call(job_data: running_job.arguments.fetch('job_data'))
    end.not_to raise_error
  ensure
    runtime&.stop
  end

  def app
    Rails.application
  end

  it_behaves_like 'framework workflow worker e2e', backend_identifier: 'redis'
  it_behaves_like 'framework delayed scheduling e2e', backend_identifier: 'redis'
end
