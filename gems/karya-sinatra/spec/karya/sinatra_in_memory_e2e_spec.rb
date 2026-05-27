# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'
require 'json'
require 'fileutils'
require 'tmpdir'

RSpec.describe Karya::Sinatra, :dashboard_manifest_fixture, :integration do
  if ENV['E2E'] == '1'
    require 'rack'
    require 'rack/test'
    include Rack::Test::Methods
  end

  def with_dummy_app(source_dir)
    Dir.mktmpdir('karya-sinatra-') do |root|
      app_root = File.join(root, 'app')
      FileUtils.copy_entry(source_dir, app_root)
      app, = Rack::Builder.parse_file(File.join(app_root, 'config.ru'))
      yield app_root, app
    end
  end

  around do |example|
    original_framework_authorizer = described_class.operator_authorizer
    original_global_authorizer = Karya.operator_authorizer if Karya.instance_variable_defined?(:@operator_authorizer)
    source_dir = File.expand_path('../dummy/modular', __dir__)
    described_class.configure_operator_authorizer(->(_request_context) { true })
    with_in_memory_backend do
      with_dummy_app(source_dir) do |app_root, rack_app|
        self.current_app_root = app_root
        self.current_rack_app = rack_app
        example.run
      end
    end
  ensure
    Karya.configure_operator_authorizer(original_global_authorizer)
    described_class.configure_operator_authorizer(original_framework_authorizer)
    self.current_app_root = nil
    self.current_rack_app = nil
  end

  def app
    current_rack_app
  end

  it 'serves the packaged dashboard document' do
    get '/karya', {}, { 'HTTP_HOST' => 'localhost' }

    expect(last_response.status).to eq(200)
    expect_dashboard_document(last_response.body, mount_path: '/karya', title: 'Karya Dashboard')
  end

  it 'uses the configured InMemory backend through the Sinatra host route' do
    get '/karya/runtime-probe', {}, { 'HTTP_HOST' => 'localhost' }

    expect(last_response.status).to eq(200)
    payload = JSON.parse(last_response.body)
    expect(payload.fetch('backend')).to eq('in_memory')
    expect(payload.fetch('job_id')).to start_with('sinatra-modular-probe-')
  end

  it 'exposes health, readiness, and operator payloads through the Sinatra host routes' do
    get '/karya/health', {}, { 'HTTP_HOST' => 'localhost' }
    expect(JSON.parse(last_response.body)).to include('status' => 'ok', 'backend' => 'in_memory')

    get '/karya/readiness', {}, { 'HTTP_HOST' => 'localhost' }
    expect(JSON.parse(last_response.body)).to include('status' => 'ready', 'backend' => 'in_memory')

    get '/karya/operator-probe', {}, { 'HTTP_HOST' => 'localhost' }
    expect(JSON.parse(last_response.body)).to include('backend' => 'in_memory', 'mount_path' => '/karya')
  end

  it_behaves_like 'framework workflow worker e2e', backend_identifier: 'in_memory'
  it_behaves_like 'framework delayed scheduling e2e', backend_identifier: 'in_memory'
end
