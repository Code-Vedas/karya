# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe Karya::Backend::Postgres do
  subject(:backend) { described_class.new(url: 'postgres://example.test/karya') }

  let(:fake_connection_class) do
    result_class = Class.new do
      def initialize(rows)
        @rows = rows
      end

      def ntuples
        @rows.length
      end

      def [](index)
        @rows.fetch(index)
      end
    end

    Class.new do
      define_singleton_method(:result_class) { result_class }

      def initialize
        @rows = {}
      end

      def exec(_sql)
        self.class.result_class.new([])
      end

      def exec_params(sql, params)
        namespace = params.fetch(0)

        if sql.include?('SELECT payload')
          payload = @rows[namespace]
          rows = payload ? [{ 'payload' => payload }] : []
          return self.class.result_class.new(rows)
        end

        @rows[namespace] = params.fetch(1) if sql.include?('INSERT INTO karya_queue_store_states')
        self.class.result_class.new([])
      end

      def close
        @closed = true
      end
    end
  end

  def standalone_queue_store_script
    <<~RUBY
      module Kernel
        alias_method :__karya_original_require_for_standalone_pg, :require

        def require(name)
          return true if name == 'pg'

          __karya_original_require_for_standalone_pg(name)
        end
      end

      require 'karya/queue_store/postgres'

      module PG
        class FakeResult
          def initialize(rows)
            @rows = rows
          end

          def ntuples
            @rows.length
          end

          def [](index)
            @rows.fetch(index)
          end
        end

        class FakeConnection
          def initialize
            @rows = {}
          end

          def exec(_sql)
            FakeResult.new([])
          end

          def exec_params(sql, params)
            namespace = params.fetch(0)
            if sql.include?('SELECT payload')
              payload = @rows[namespace]
              return FakeResult.new([]) unless payload

              return FakeResult.new([{ 'payload' => payload }])
            end

            if sql.include?('INSERT INTO karya_queue_store_states')
              @rows[namespace] = params.fetch(1)
              return FakeResult.new([])
            end

            FakeResult.new([])
          end
        end

        class << self
          def connect(_url)
            @connection ||= FakeConnection.new
          end
        end
      end

      now = Time.utc(2026, 5, 5, 12, 0, 0)
      store = Karya::QueueStore::Postgres.new(url: 'postgres://example.test/karya', namespace: 'standalone')
      job = Karya::Job.new(id: 'job-1', queue: 'billing', handler: 'billing_sync', state: :submission, created_at: now)
      store.enqueue(job:, now: now + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: now + 2)
      store.start_execution(reservation_token: reservation.token, now: now + 3)
      failed = store.fail_execution(reservation_token: reservation.token, now: now + 4, failure_classification: :error)
      puts failed.state
    RUBY
  end

  it 'loads as a standalone backend file' do
    lib_path = File.expand_path('../../../lib', __dir__)
    script = <<~RUBY
      require 'karya/backend/postgres'
      puts Karya::Backend::Postgres.new(url: 'postgres://example.test/karya').identifier
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status.success?).to be(true), stderr
    expect(stdout).to eq("postgres\n")
  end

  it 'loads Postgres queue-store execution paths as a standalone file' do
    lib_path = File.expand_path('../../../lib', __dir__)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', standalone_queue_store_script)

    expect(status.success?).to be(true), stderr
    expect(stdout).to eq("failed\n")
  end

  it 'raises an actionable load error when the pg gem is not available' do
    lib_path = File.expand_path('../../../lib', __dir__)
    script = <<~RUBY
      module Kernel
        alias_method :__karya_original_require_for_pg_spec, :require

        def require(name)
          raise LoadError, 'cannot load such file -- pg' if name == 'pg'

          __karya_original_require_for_pg_spec(name)
        end
      end

      begin
        require 'karya/backend/postgres'
        Karya::Backend::Postgres.new(url: 'postgres://example.test/karya').build_queue_store
      rescue LoadError => e
        warn e.message
        exit 0
      end

      exit 1
    RUBY

    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status.success?).to be(true)
    expect(stderr).to include("Add `gem 'pg'` to your Gemfile to use Karya::Backend::Postgres and Karya::QueueStore::Postgres.")
  end

  it 'raises an actionable load error from the dependency loader when pg is unavailable' do
    dependency_loader = Karya::QueueStore::Postgres.send(:const_get, :Internal).const_get(:DependencyLoader)
    allow(dependency_loader).to receive(:require).with('pg').and_raise(LoadError, 'cannot load such file -- pg')

    expect do
      dependency_loader.require_pg!
    end.to raise_error(
      LoadError,
      /Add `gem 'pg'` to your Gemfile to use Karya::Backend::Postgres and Karya::QueueStore::Postgres\./
    )
  end

  it 'exposes the backend identifier' do
    expect(backend.identifier).to eq('postgres')
  end

  it 'builds the Postgres queue store owned by the backend definition' do
    allow(Karya::QueueStore::Postgres.send(:const_get, :Internal).const_get(:DependencyLoader)).to receive(:require_pg!).and_return(true)
    stub_const('PG', Module.new) unless defined?(PG)
    allow(PG).to receive(:connect).with('postgres://example.test/karya').and_return(fake_connection)

    queue_store = backend.build_queue_store

    expect(queue_store).to be_a(Karya::QueueStore::Postgres)
  end

  it 'forwards namespace and queue-store options to the queue store' do
    allow(Karya::QueueStore::Postgres.send(:const_get, :Internal).const_get(:DependencyLoader)).to receive(:require_pg!).and_return(true)
    stub_const('PG', Module.new) unless defined?(PG)
    allow(PG).to receive(:connect).with('postgres://example.test/karya').and_return(fake_connection)

    queue_store = described_class.new(
      url: 'postgres://example.test/karya',
      namespace: 'payments',
      max_batch_size: 50
    ).build_queue_store

    expect(queue_store.send(:namespace)).to eq('payments')
    expect(queue_store.send(:max_batch_size)).to eq(50)
  end

  it 'normalizes invalid queue-store keyword errors into backend configuration errors' do
    allow(Karya::QueueStore::Postgres.send(:const_get, :Internal).const_get(:DependencyLoader)).to receive(:require_pg!).and_return(true)
    stub_const('PG', Module.new) unless defined?(PG)
    allow(PG).to receive(:connect).with('postgres://example.test/karya').and_return(fake_connection)

    backend = described_class.new(
      url: 'postgres://example.test/karya',
      namespace: 'payments',
      unsupported_option: true
    )

    expect do
      backend.build_queue_store
    end.to raise_error(
      Karya::InvalidBackendConfigurationError,
      /invalid Postgres backend queue-store configuration: unexpected option keys :unsupported_option: unknown keywords: unsupported_option/
    ) { |error| expect(error.cause).to be_a(ArgumentError) }
  end

  it 'normalizes queue-store validation failures into backend configuration errors' do
    backend = described_class.new(url: ' ', namespace: 'payments')

    expect do
      backend.build_queue_store
    end.to raise_error(
      Karya::InvalidBackendConfigurationError,
      /invalid Postgres backend queue-store configuration: url must be a non-empty String/
    ) { |error| expect(error.cause).to be_a(Karya::InvalidQueueStoreOperationError) }
  end

  it 'declares no-op lifecycle hooks around queue-store usage' do
    allow(Karya::QueueStore::Postgres.send(:const_get, :Internal).const_get(:DependencyLoader)).to receive(:require_pg!).and_return(true)
    stub_const('PG', Module.new) unless defined?(PG)
    allow(PG).to receive(:connect).with('postgres://example.test/karya').and_return(fake_connection)
    queue_store = backend.build_queue_store

    expect(backend.before_start(queue_store:)).to be_nil
    expect(backend.after_stop(queue_store:)).to be_nil
  end

  def fake_connection
    @fake_connection ||= fake_connection_class.new
  end
end
