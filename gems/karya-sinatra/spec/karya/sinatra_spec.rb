# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'rake'

RSpec.describe Karya::Sinatra, :dashboard_manifest_fixture do
  let(:backend_class) do
    Class.new do
      include Karya::Backend::Base

      def identifier = 'test'
      def build_queue_store = Karya::QueueStore::InMemory.new(token_generator: -> { 'lease-token' })
    end
  end

  around do |example|
    original_global_authorizer = Karya.operator_authorizer if Karya.instance_variable_defined?(:@operator_authorizer)
    original_framework_authorizer = described_class.operator_authorizer
    example.run
  ensure
    Karya::Hooks.reset!
    Karya.configure_operator_authorizer(original_global_authorizer)
    described_class.configure_operator_authorizer(original_framework_authorizer)
    described_class.instance_variable_set(:@support, nil)
    Karya::FrameworkRuntime.reset_shared_runtime!
  end

  it 'exposes framework-native job configuration defaults and task wiring' do
    configuration = described_class.configuration

    expect(described_class::Job < Karya::FrameworkJob::Base).to be(true)
    expect(configuration.job_paths).to eq(['app/jobs'])
    expect(configuration.boot_files).to eq([])
    expect(Rake::Task.task_defined?('karya:work')).to be(true) if defined?(Rake::Task)
  end

  it 'exposes the version, root path, migrations, and dashboard helpers' do
    expect(described_class::VERSION).to eq('0.1.0')
    expect(described_class.framework_root_path).to eq(Dir.pwd)

    Dir.mktmpdir('karya-sinatra-migration-') do |dir|
      host = Object.new
      host.extend(described_class)
      postgres_path = Karya::Sequel.install_postgres_migration(target_dir: dir)
      mysql_path = Karya::Sequel.install_mysql_migration(target_dir: dir)
      sqlite_path = Karya::Sequel.install_sqlite_migration(target_dir: dir)
      host.send(:build_host_runtime, backend_class:, backend_options: {})
      host.send(:with_host_runtime, backend_class:, backend_options: {}, &:health_payload)

      expect(File.read(postgres_path)).to include('create_table?(:karya_queue_store_states)')
      expect(File.read(mysql_path)).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_states')
      expect(File.read(sqlite_path)).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_states')
    end

    expect_dashboard_document(described_class.render_dashboard_page, mount_path: '/karya', title: 'Karya Dashboard')
    expect(described_class.mount_path(scope: 'ops')).to eq('/ops/karya')
  end

  it 'supports default runtime and migration arguments on the public module API' do
    runtime = instance_double(Karya::FrameworkRuntime::HostRuntime)
    allow(Karya::FrameworkRuntime).to receive(:with_started_runtime).and_yield(runtime)

    described_class.with_host_runtime { |_runtime| nil }

    expect(Karya::FrameworkRuntime).to have_received(:with_started_runtime).with(
      backend_class: Karya.backend_class,
      backend_options: Karya.backend_options
    )
  end

  it 'exposes support and build/runtime helpers on the framework module' do
    allow(described_class.support).to receive_messages(
      configuration: :configuration,
      runtime_inspect: { 'state' => 'running' },
      runtime_drain: { 'ok' => true },
      runtime_force_stop: { 'ok' => true }
    )

    expect(described_class.support).to be_a(Karya::Internal::FrameworkSupport)
    expect(described_class.configuration).to eq(:configuration)
    expect(described_class.runtime_inspect(queues: ['billing'])).to eq('state' => 'running')
    expect(described_class.runtime_drain(queues: ['billing'])).to eq('ok' => true)
    expect(described_class.runtime_force_stop(queues: ['billing'])).to eq('ok' => true)
  end

  it 'builds host runtime payloads and framework-native enqueue helpers' do
    allow(Karya::FrameworkRuntime).to receive(:shared_runtime).and_call_original
    allow(Karya::FrameworkRuntime).to receive(:with_started_runtime).and_call_original
    queue_store = instance_double(Karya::QueueStore::Base, enqueue: nil)
    Karya.configure_queue_store(queue_store)

    expect(described_class.build_host_runtime(backend_class:, backend_options: {})).to be_a(Karya::FrameworkRuntime::HostRuntime)
    expect(described_class.health_payload(backend_class:, backend_options: {})).to include('status' => 'ok', 'backend' => 'test')
    expect(described_class.readiness_payload(backend_class:, backend_options: {})).to include('status' => 'ready', 'backend' => 'test')
    expect(described_class.operator_payload(backend_class:, backend_options: {}, scope: 'ops')).to include('mount_path' => '/ops/karya')
    expect(described_class.runtime_probe_payload(backend_class:, backend_options: {}).fetch('job_id')).to start_with('sinatra-modular-probe-')
    probe_job = Class.new(described_class::Job) do
      karya_handler 'SyncAccountJob'

      def perform(account_id:)
        account_id
      end
    end
    expect(probe_job.set(queue: :billing).perform_later(account_id: 1)).to be_a(Karya::Job)
    expect(queue_store).to have_received(:enqueue)
    expect(Karya::FrameworkRuntime).to have_received(:shared_runtime).exactly(4).times
    expect(Karya::FrameworkRuntime).not_to have_received(:with_started_runtime)
  ensure
    Karya.configure_queue_store(nil)
  end

  it 'supports authorizers, queue parsing, karya.yml overrides, and worker delegation' do
    expect(described_class.operator_access_authorized?(:anon)).to be(false)
    described_class.configure_operator_authorizer(->(request_context) { request_context == :framework })
    expect(described_class.operator_access_authorized?(:framework)).to be(true)
    expect(described_class.operator_access_authorized?(:blocked)).to be(false)
    expect(described_class.operator_access_authorized?(:global, authorizer: ->(request_context) { request_context == :global })).to be(true)
    expect do
      described_class.configure_operator_authorizer(Object.new)
    end.to raise_error(ArgumentError, /must respond to #call/)

    Dir.mktmpdir('karya-sinatra-config-') do |root|
      path = File.join(root, 'karya.yml')
      File.write(path, <<~YAML)
        defaults:
          backend: sqlite
          backend_config:
            url: sqlite3:///tmp/sinatra.sqlite3
          job_paths:
            - app/jobs
            - lib/jobs
          boot_files:
            - config/boot/jobs.rb
      YAML
      described_class.instance_variable_set(:@support, nil)
      described_class.load_config_file!(path:)
    end
    expect(described_class.configuration.job_paths).to eq(['app/jobs', 'lib/jobs'])
    expect(described_class.configuration.boot_files).to eq(['config/boot/jobs.rb'])
    expect(Karya::Internal::FrameworkRuntimeIdentity.parse_queues('billing,critical')).to eq(%w[billing critical])
    expect { Karya::Internal::FrameworkRuntimeIdentity.parse_queues(nil) }.to raise_error(ArgumentError, /at least one queue is required/)

    handlers = { 'BillingSyncJob' => Class.new(Karya::Sinatra::Job) { def perform; end } }
    allow(Karya::FrameworkJob::Discovery).to receive(:new).and_return(instance_double(Karya::FrameworkJob::Discovery, handlers:))
    allow(Karya::FrameworkJob::WorkerRunner).to receive(:run).and_return(:ok)

    expect(described_class.support.run_worker(queues: ['billing'], threads: 2)).to eq(:ok)
    expect { described_class::RakeTasks.load! }.not_to raise_error
  end

  it 'normalizes queue arguments for the worker task path' do
    expect(Karya::Internal::FrameworkRuntimeIdentity.parse_queues('billing,critical')).to eq(%w[billing critical])
  end

  it 'registers workflow sources through the framework configuration' do
    source = Module.new
    allow(described_class.configuration).to receive(:register_workflows).and_return([source])

    expect(described_class.register_workflows(source)).to eq([source])
    expect(described_class.configuration).to have_received(:register_workflows).with(source)
  end

  it 'invokes the karya:work rake task through the registered block' do
    Rake::Task['karya:work'].reenable
    allow(described_class.support).to receive(:run_worker).and_return(:ok)
    allow(Karya::FrameworkJob::RuntimeOptions).to receive(:from_env).and_return({})

    Rake::Task['karya:work'].invoke('billing')

    expect(described_class.support).to have_received(:run_worker).with(queues: ['billing'], name: nil)
  end
end
