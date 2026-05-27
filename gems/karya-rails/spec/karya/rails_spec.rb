# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'active_job'
require 'rake'
require_relative '../rails_helper'

RSpec.describe Karya::Rails, :dashboard_manifest_fixture do
  let(:backend_class) do
    Class.new do
      include Karya::Backend::Base

      def identifier = 'test'
      def build_queue_store = Karya::QueueStore::InMemory.new(token_generator: -> { 'lease-token' })
    end
  end

  around do |example|
    original_global_authorizer = Karya.operator_authorizer if Karya.instance_variable_defined?(:@operator_authorizer)
    original_rails_authorizer = described_class.operator_authorizer
    example.run
  ensure
    Karya::Hooks.reset!
    Karya.configure_operator_authorizer(original_global_authorizer)
    described_class.configure_operator_authorizer(original_rails_authorizer)
    described_class.instance_variable_set(:@support, nil)
    Karya::FrameworkRuntime.reset_shared_runtime!
  end

  it 'exposes the version' do
    expect(described_class::VERSION).to eq('0.1.0')
  end

  it 'exposes the framework root path' do
    expect(described_class.framework_root_path).to eq(Rails.root.to_s)
  end

  it 'loads static backend and discovery settings from karya.yml' do
    Dir.mktmpdir('karya-rails-config-') do |root|
      path = File.join(root, 'karya.yml')
      File.write(path, <<~YAML)
        defaults:
          backend: sqlite
          backend_config:
            url: sqlite3:///tmp/rails.sqlite3
          job_paths:
            - app/jobs
            - lib/jobs
          boot_files:
            - config/boot/jobs.rb
      YAML
      described_class.instance_variable_set(:@support, nil)
      described_class.load_config_file!(path:)

      expect(described_class.configuration.job_paths).to eq(['app/jobs', 'lib/jobs'])
      expect(described_class.configuration.boot_files).to eq(['config/boot/jobs.rb'])
      expect(Karya.backend_class).to eq(Karya::Backend::SQLite)
      expect(Karya.backend_options).to eq(url: 'sqlite3:///tmp/rails.sqlite3')
    end
  end

  it 'registers workflow sources through the framework configuration' do
    source = Module.new
    allow(described_class.configuration).to receive(:register_workflows).and_return([source])

    expect(described_class.register_workflows(source)).to eq([source])
    expect(described_class.configuration).to have_received(:register_workflows).with(source)
  end

  it 'exposes a framework-native job base and discovers native Rails jobs' do
    expect(described_class::Job < Karya::FrameworkJob::Base).to be(true)
    expect(
      described_class.support.worker_handlers(
        extra_handlers: { Karya::ActiveJob.handler_name => described_class.active_job_handler },
        eager_load: -> { Rails.application.eager_load! }
      )
    ).to include(
      'Karya::NativeDummyJob' => Karya::NativeDummyJob,
      Karya::ActiveJob.handler_name => described_class.active_job_handler
    )
    expect(
      described_class.support.worker_handlers(eager_load: -> { Rails.application.eager_load! })
    ).to include(
      'Karya::NativeDummyJob' => Karya::NativeDummyJob
    )
    expect(
      described_class.support.worker_handlers(eager_load: -> { Rails.application.eager_load! })
    ).not_to include(Karya::ActiveJob.handler_name)
  end

  it 'delegates Postgres migration install through the folded Active Record support' do
    Dir.mktmpdir('karya-rails-migration-') do |dir|
      path = Karya::ActiveRecord.install_postgres_migration(target_dir: dir)

      expect(File.basename(path)).to match(/\A\d{14}_create_karya_postgres_backend\.rb\z/)
      expect(File.read(path)).to include('create_table :karya_queue_store_states')
    end
  end

  it 'delegates MySQL migration install through the folded Active Record support' do
    Dir.mktmpdir('karya-rails-mysql-migration-') do |dir|
      path = Karya::ActiveRecord.install_mysql_migration(target_dir: dir)

      expect(File.basename(path)).to match(/\A\d{14}_create_karya_mysql_backend\.rb\z/)
      expect(File.read(path)).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_states')
    end
  end

  it 'delegates SQLite migration install through the folded Active Record support' do
    Dir.mktmpdir('karya-rails-sqlite-migration-') do |dir|
      path = Karya::ActiveRecord.install_sqlite_migration(target_dir: dir)

      expect(File.basename(path)).to match(/\A\d{14}_create_karya_sqlite_backend\.rb\z/)
      expect(File.read(path)).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_states')
    end
  end

  it 'renders the dashboard document for the mounted Rails path' do
    document = described_class.render_dashboard_page

    expect_dashboard_document(document, mount_path: '/karya', title: 'Karya Dashboard')
  end

  it 'builds a scoped mount path when scope is provided' do
    document = described_class.render_dashboard_page(scope: '//ops//')

    expect_dashboard_document(document, mount_path: '/ops/karya', title: 'Karya Dashboard')
  end

  it 'rejects combining scope and mount_path' do
    expect do
      described_class.render_dashboard_page(scope: 'ops', mount_path: '/custom/karya')
    end.to raise_error(ArgumentError, 'scope and mount_path cannot be combined')
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
    expect(described_class.health_payload(backend_class:, backend_options: {})).to include(
      'status' => 'ok',
      'backend' => 'test'
    )
    expect(described_class.readiness_payload(backend_class:, backend_options: {})).to include(
      'status' => 'ready',
      'backend' => 'test'
    )
    expect(described_class.operator_payload(backend_class:, backend_options: {})).to include(
      'backend' => 'test',
      'mount_path' => '/karya'
    )
    expect(described_class.runtime_probe_payload(backend_class:, backend_options: {}).fetch('job_id')).to start_with('rails-probe-')
    expect(Karya::FrameworkRuntime).to have_received(:shared_runtime).exactly(4).times
    expect(Karya::FrameworkRuntime).not_to have_received(:with_started_runtime)
  end

  it 'enqueues framework-authored jobs through the configured queue store' do
    queue_store = instance_double(Karya::QueueStore::Base, enqueue: nil)
    Karya.configure_queue_store(queue_store)

    job = Class.new(described_class::Job) do
      karya_handler 'DashboardProbeJob'

      def perform(attempt:)
        attempt
      end
    end.set(queue: 'dashboard', job_id: 'rails-enqueue-job').perform_later(attempt: 1)

    expect(job).to be_a(Karya::Job)
    expect(queue_store).to have_received(:enqueue)
  ensure
    Karya.configure_queue_store(nil)
  end

  it 'runs framework workers through the shared worker runner' do
    handlers = { 'Karya::NativeDummyJob' => Karya::NativeDummyJob }
    allow(Karya::FrameworkJob::Discovery).to receive(:new).and_return(instance_double(Karya::FrameworkJob::Discovery, handlers:))
    allow(Karya::FrameworkJob::WorkerRunner).to receive(:run).and_return(:ok)

    result = described_class.support.run_worker(queues: ['billing'], threads: 4, eager_load: -> { Rails.application.eager_load! })

    expect(result).to eq(:ok)
    expect(Karya::FrameworkJob::WorkerRunner).to have_received(:run).with(
      queues: ['billing'],
      handlers:,
      threads: 4,
      worker_id: 'rails-billing',
      state_file: Rails.root.join('tmp/karya/workers/billing.json').to_s
    )
  end

  it 'supports framework-native job authoring and enqueue helpers' do
    queue_store = instance_double(Karya::QueueStore::Base, enqueue: nil)
    Karya.configure_queue_store(queue_store)

    result = Karya::NativeDummyJob.perform_now('hello', force: true)
    job = Karya::NativeDummyJob.perform_later('hello', force: true)

    expect(result).to eq(['hello', true])
    expect(job.queue).to eq('native_dashboard')
    expect(job.handler).to eq('Karya::NativeDummyJob')
    expect(queue_store).to have_received(:enqueue)
  ensure
    Karya.configure_queue_store(nil)
  end

  it 'supports an operator authorizer seam' do
    described_class.configure_operator_authorizer(->(request_context) { request_context == :allowed })

    expect(described_class.operator_access_authorized?(:allowed)).to be(true)
    expect(described_class.operator_access_authorized?(:blocked)).to be(false)
  end

  it 'denies operator access when no authorizer is configured and rejects invalid authorizers' do
    expect(described_class.operator_access_authorized?(:anyone)).to be(false)

    expect do
      described_class.configure_operator_authorizer(Object.new)
    end.to raise_error(ArgumentError, 'operator authorizer must respond to #call')
  end

  it 'falls back to the process-wide operator authorizer and lets explicit authorizers win' do
    Karya.configure_operator_authorizer(->(request_context) { request_context == :global })
    described_class.configure_operator_authorizer(->(request_context) { request_context == :framework })

    expect(described_class.operator_access_authorized?(:framework)).to be(true)
    expect(described_class.operator_access_authorized?(:global)).to be(false)
    expect(described_class.operator_access_authorized?(:global, authorizer: ->(request_context) { request_context == :global })).to be(true)
  end

  it 'lets operator authorization hooks override the resolved decision' do
    described_class.configure_operator_authorizer(->(_request_context) { true })
    Karya::Hooks.register(:operator_authorization, ->(_payload) { false })

    expect(described_class.operator_access_authorized?(:allowed)).to be(false)
  end

  it 'exposes the ActiveJob queue adapter and active job handler' do
    queue_store = instance_double(Karya::QueueStore::Base)
    enqueue_calls = []
    allow(queue_store).to receive(:enqueue) do |job:, now:|
      enqueue_calls << [job, now]
    end
    Karya.configure_queue_store(queue_store)

    stub_const('ApplicationJob', ActiveJob::Base) unless defined?(ApplicationJob)

    dummy_job_class = Class.new(ApplicationJob) do
      queue_as :dashboard

      def perform(message)
        message
      end
    end
    stub_const('Karya::RailsSpecJob', dummy_job_class)

    described_class.active_job_queue_adapter.enqueue(Karya::RailsSpecJob.new('hello'))

    enqueued_job = enqueue_calls.fetch(0).fetch(0)
    expect(enqueued_job.handler).to eq(Karya::ActiveJob.handler_name)
    expect(enqueued_job.queue).to eq('dashboard')
    expect(enqueued_job.arguments.fetch('job_data')).to include('job_class' => 'Karya::RailsSpecJob')
    expect(described_class.active_job_queue_adapter.enqueue_after_transaction_commit?).to be(false)
    expect(described_class.active_job_handler).to eq(Karya::ActiveJob.handler)
  ensure
    Karya.configure_queue_store(nil)
  end

  it 'raises when delayed ActiveJob enqueue lacks Kaal delayed-job support' do
    stub_const('ApplicationJob', ActiveJob::Base) unless defined?(ApplicationJob)

    delayed_job_class = Class.new(ApplicationJob) do
      queue_as :dashboard

      def perform(message)
        message
      end
    end
    stub_const('Karya::RailsDelayedJob', delayed_job_class)
    allow(Kaal).to receive(:configuration).and_return(double(backend: nil))

    expect do
      described_class.active_job_queue_adapter.enqueue_at(
        Karya::RailsDelayedJob.new('hello later'),
        Time.now.utc + 3600
      )
    end.to raise_error(Karya::UnsupportedSchedulingError, /requires Kaal with delayed-job support/)
  end

  it 'exposes framework config loading and runtime-control delegation' do
    allow(described_class.support).to receive_messages(
      configuration: :configuration,
      load_config_file!: :configuration,
      runtime_inspect: { 'state' => 'running' },
      runtime_drain: { 'ok' => true },
      runtime_force_stop: { 'ok' => true }
    )

    expect(described_class.load_config_file!).to eq(:configuration)
    expect(described_class.configuration).to eq(:configuration)
    expect(described_class.runtime_inspect(queues: ['billing'])).to eq('state' => 'running')
    expect(described_class.runtime_drain(queues: ['billing'])).to eq('ok' => true)
    expect(described_class.runtime_force_stop(queues: ['billing'])).to eq('ok' => true)
  end

  it 'loads and invokes the packaged install rake tasks' do
    original_rake = Rake.application
    rake = Rake::Application.new
    installer = ->(**) {}

    Rake.application = rake
    Rake::Task.define_task(:environment)
    allow(Rails).to receive(:root).and_return(Pathname('/tmp/app'))
    allow(Karya::Internal::FrameworkInstaller).to receive_messages(
      migration_kind: :sqlite,
      active_record_migration_installer: installer,
      install!: nil,
      install_migrations!: nil
    )

    load File.expand_path('../../lib/tasks/karya_rails_tasks.rake', __dir__)
    Rake::Task['karya:install:all'].invoke('sqlite')
    Rake::Task['karya:install:migrations'].invoke('sqlite')

    expect(Karya::Internal::FrameworkInstaller).to have_received(:install!)
    expect(Karya::Internal::FrameworkInstaller).to have_received(:install_migrations!)
  ensure
    Rake.application = original_rake
  end
end
