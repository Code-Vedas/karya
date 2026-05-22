# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Hanami, :dashboard_manifest_fixture do
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

  it 'exposes the version' do
    expect(described_class::VERSION).to eq('0.1.0')
  end

  it 'exposes the framework root path' do
    expect(described_class.framework_root_path).to eq(Dir.pwd)
  end

  it 'falls back to the shared runtime-context environment resolver when Hanami env is unavailable' do
    hide_const('Hanami')
    described_class.instance_variable_set(:@support, nil)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('HANAMI_ENV').and_return(' ')
    allow(Karya::Internal::Config::RuntimeContext).to receive(:environment_name_from).with(ENV).and_return('staging')

    resolved_environment = described_class.support.send(:environment_name_resolver).call

    expect(resolved_environment).to eq('staging')
  end

  it 'exposes framework-native job configuration defaults and loads static config from karya.yml' do
    configuration = described_class.configuration

    expect(described_class::Job < Karya::FrameworkJob::Base).to be(true)
    expect(configuration.job_paths).to eq(['app/jobs'])
    expect(configuration.boot_files).to eq([])

    Dir.mktmpdir('karya-hanami-config-') do |root|
      path = File.join(root, 'karya.yml')
      File.write(path, <<~YAML)
        defaults:
          backend: sqlite
          backend_config:
            url: sqlite3:///tmp/hanami.sqlite3
          job_paths:
            - app/jobs
            - components/jobs
          boot_files:
            - config/boot/jobs.rb
      YAML
      described_class.instance_variable_set(:@support, nil)
      described_class.load_config_file!(path:)

      expect(described_class.configuration.job_paths).to eq(['app/jobs', 'components/jobs'])
      expect(described_class.configuration.boot_files).to eq(['config/boot/jobs.rb'])
    end
  end

  it 'delegates migration install through the folded Sequel support' do
    Dir.mktmpdir('karya-hanami-migration-') do |dir|
      postgres_path = Karya::Sequel.install_postgres_migration(target_dir: dir)
      mysql_path = Karya::Sequel.install_mysql_migration(target_dir: dir)
      sqlite_path = Karya::Sequel.install_sqlite_migration(target_dir: dir)
      host = Object.new
      host.extend(described_class)
      host.send(:build_host_runtime, backend_class:, backend_options: {})

      expect(File.read(postgres_path)).to include('create_table?(:karya_queue_store_states)')
      expect(File.read(mysql_path)).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_states')
      expect(File.read(sqlite_path)).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_states')
    end
  end

  it 'discovers and runs framework-native workers through the shared runner' do
    handlers = { 'BillingSyncJob' => Class.new(Karya::Hanami::Job) { def perform; end } }
    allow(Karya::FrameworkJob::Discovery).to receive(:new).and_return(instance_double(Karya::FrameworkJob::Discovery, handlers:))
    allow(Karya::FrameworkJob::WorkerRunner).to receive(:run).and_return(:ok)

    result = described_class.support.run_worker(queues: ['billing'], processes: 2)

    expect(result).to eq(:ok)
    expect(Karya::FrameworkJob::WorkerRunner).to have_received(:run).with(
      queues: ['billing'],
      handlers:,
      processes: 2,
      worker_id: 'hanami-billing',
      state_file: File.join(Dir.pwd, 'tmp', 'karya', 'workers', 'billing.json')
    )
  end

  it 'parses queue arguments for the worker command path' do
    expect(Karya::Internal::FrameworkRuntimeIdentity.parse_queues('billing,critical')).to eq(%w[billing critical])
    expect { Karya::Internal::FrameworkRuntimeIdentity.parse_queues(nil) }.to raise_error(ArgumentError, /at least one queue is required/)
  end

  it 'renders the dashboard document for the Hanami mount path' do
    expect_dashboard_document(described_class.render_dashboard_page, mount_path: '/karya', title: 'Karya Dashboard')
  end

  it 'builds normalized mount paths' do
    expect(described_class.mount_path(prefix: 'admin')).to eq('/admin/karya')
    expect(described_class.mount_path(prefix: '//ops//')).to eq('/ops/karya')
    expect(described_class.mount_path(prefix: '///')).to eq('/karya')
  end

  it 'passes through with_host_runtime defaults to the shared framework runtime builder' do
    runtime = instance_double(Karya::FrameworkRuntime::HostRuntime)
    allow(Karya::FrameworkRuntime).to receive(:with_started_runtime).and_yield(runtime)

    described_class.with_host_runtime { |_runtime| nil }

    expect(Karya::FrameworkRuntime).to have_received(:with_started_runtime).with(
      backend_class: Karya.backend_class,
      backend_options: Karya.backend_options
    )
  end

  it 'builds shared host runtime payloads through the core framework runtime contract' do
    allow(Karya::FrameworkRuntime).to receive(:shared_runtime).and_call_original
    allow(Karya::FrameworkRuntime).to receive(:with_started_runtime).and_call_original
    runtime = described_class.build_host_runtime(backend_class:, backend_options: {})

    expect(runtime).to be_a(Karya::FrameworkRuntime::HostRuntime)
    expect(described_class.health_payload(backend_class:, backend_options: {})).to include('status' => 'ok', 'backend' => 'test')
    expect(described_class.readiness_payload(backend_class:, backend_options: {})).to include('status' => 'ready', 'backend' => 'test')
    expect(described_class.operator_payload(backend_class:, backend_options: {},
                                            prefix: 'admin')).to include('backend' => 'test',
                                                                         'mount_path' => '/admin/karya')
    expect(described_class.runtime_probe_payload(backend_class:, backend_options: {}).fetch('job_id')).to start_with('hanami-probe-')
    expect(Karya::FrameworkRuntime).to have_received(:shared_runtime).exactly(4).times
    expect(Karya::FrameworkRuntime).not_to have_received(:with_started_runtime)
  end

  it 'exposes support and runtime-control delegation on the framework module' do
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

  it 'registers workflow sources through the framework configuration' do
    source = Module.new
    allow(described_class.configuration).to receive(:register_workflows).and_return([source])

    expect(described_class.register_workflows(source)).to eq([source])
    expect(described_class.configuration).to have_received(:register_workflows).with(source)
  end

  it 'enqueues framework-authored jobs through the configured queue store' do
    queue_store = instance_double(Karya::QueueStore::Base, enqueue: nil)
    Karya.configure_queue_store(queue_store)

    job = Class.new(described_class::Job) do
      karya_handler 'DashboardProbeJob'

      def perform(attempt:)
        attempt
      end
    end.set(queue: 'dashboard', job_id: 'hanami-enqueue-job').perform_later(attempt: 1)

    expect(job).to be_a(Karya::Job)
    expect(queue_store).to have_received(:enqueue)
  ensure
    Karya.configure_queue_store(nil)
  end

  it 'supports framework and process-wide operator authorizers with explicit precedence' do
    expect(described_class.operator_access_authorized?(:anonymous)).to be(false)

    described_class.configure_operator_authorizer(->(request_context) { request_context == :framework })
    expect(described_class.operator_access_authorized?(:framework)).to be(true)
    expect(described_class.operator_access_authorized?(:global)).to be(false)

    Karya.configure_operator_authorizer(->(request_context) { request_context == :global })
    expect(described_class.operator_access_authorized?(:framework)).to be(true)
    expect(described_class.operator_access_authorized?(:global)).to be(false)
    expect(described_class.operator_access_authorized?(:global, authorizer: ->(request_context) { request_context == :global })).to be(true)
  end

  it 'rejects invalid operator authorizers and lets hooks override resolved decisions' do
    expect do
      described_class.configure_operator_authorizer(Object.new)
    end.to raise_error(ArgumentError, 'operator authorizer must respond to #call')

    described_class.configure_operator_authorizer(->(_request_context) { true })
    Karya::Hooks.register(:operator_authorization, ->(_payload) { false })

    expect(described_class.operator_access_authorized?(:allowed)).to be(false)
  end
end
