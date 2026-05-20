# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe Karya::Backend::MySQL do
  subject(:backend) { described_class.new(url: 'mysql2://example.test/karya') }

  let(:fake_connection_class) do
    Class.new do
      def initialize
        @rows = {}
      end

      def query(sql, **_options)
        namespace = sql[/WHERE namespace = '([^']+)'/, 1]
        if sql.include?('SELECT payload')
          payload = @rows[namespace]
          return payload ? [{ 'payload' => payload }] : []
        end

        if sql.include?('INSERT INTO karya_queue_store_states')
          values = sql.scan(/'([^']+)'/)
          @rows[values[0][0]] = values[1][0] if values.length >= 2
        end

        []
      end

      def escape(value)
        value.gsub("'", "\\\\'")
      end

      def close
        @closed = true
      end
    end
  end

  def standalone_queue_store_script
    <<~RUBY
      module Kernel
        alias_method :__karya_original_require_for_standalone_mysql, :require

        def require(name)
          return true if name == 'mysql2'

          __karya_original_require_for_standalone_mysql(name)
        end
      end

      require 'karya/queue_store/mysql'

      Object.send(:remove_const, :Mysql2) if Object.const_defined?(:Mysql2)

      module Mysql2
        class Client
          def initialize(**_options)
            @rows = {}
          end

          def query(sql, **)
            namespace = sql[/WHERE namespace = '([^']+)'/, 1]
            if sql.include?('SELECT payload')
              payload = @rows[namespace]
              return payload ? [{ 'payload' => payload }] : []
            end

            if sql.include?('INSERT INTO karya_queue_store_states')
              values = sql.scan(/'([^']+)'/)
              @rows[values[0][0]] = values[1][0] if values.length >= 2
            end

            []
          end

          def escape(value)
            value.gsub("'", "\\\\'")
          end
        end
      end

      now = Time.utc(2026, 5, 5, 12, 0, 0)
      store = Karya::QueueStore::MySQL.new(url: 'mysql2://example.test/karya', namespace: 'standalone')
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
      require 'karya/backend/mysql'
      puts Karya::Backend::MySQL.new(url: 'mysql2://example.test/karya').identifier
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status.success?).to be(true), stderr
    expect(stdout).to eq("mysql\n")
  end

  it 'loads MySQL queue-store execution paths as a standalone file' do
    lib_path = File.expand_path('../../../lib', __dir__)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', standalone_queue_store_script)

    expect(status.success?).to be(true), stderr
    expect(stdout).to eq("failed\n")
  end

  it 'raises an actionable load error when the mysql2 gem is not available' do
    lib_path = File.expand_path('../../../lib', __dir__)
    script = <<~RUBY
      module Kernel
        alias_method :__karya_original_require_for_mysql_spec, :require

        def require(name)
          raise LoadError, 'cannot load such file -- mysql2' if name == 'mysql2'

          __karya_original_require_for_mysql_spec(name)
        end
      end

      begin
        require 'karya/backend/mysql'
        Karya::Backend::MySQL.new(url: 'mysql2://example.test/karya').build_queue_store
      rescue LoadError => e
        warn e.message
        exit 0
      end

      exit 1
    RUBY

    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status.success?).to be(true)
    expect(stderr).to include("Add `gem 'mysql2'` to your Gemfile to use Karya::Backend::MySQL and Karya::QueueStore::MySQL.")
  end

  it 'raises an actionable load error from the dependency loader when mysql2 is unavailable' do
    dependency_loader = Karya::QueueStore::MySQL.send(:const_get, :Internal).const_get(:DependencyLoader)
    allow(dependency_loader).to receive(:require).with('mysql2').and_raise(LoadError, 'cannot load such file -- mysql2')

    expect do
      dependency_loader.require_mysql2!
    end.to raise_error(
      LoadError,
      /Add `gem 'mysql2'` to your Gemfile to use Karya::Backend::MySQL and Karya::QueueStore::MySQL\./
    )
  end

  it 'exposes the backend identifier' do
    expect(backend.identifier).to eq('mysql')
  end

  it 'builds the MySQL queue store owned by the backend definition' do
    allow(Karya::QueueStore::MySQL.send(:const_get, :Internal).const_get(:DependencyLoader)).to receive(:require_mysql2!).and_return(true)
    stub_const('Mysql2', Module.new) unless defined?(Mysql2)
    stub_const('Mysql2::Client', Class.new)
    allow(Mysql2::Client).to receive(:new).with(hash_including(host: 'example.test', port: 3306, database: 'karya')).and_return(fake_connection)

    queue_store = backend.build_queue_store

    expect(queue_store).to be_a(Karya::QueueStore::MySQL)
  end

  it 'forwards namespace and queue-store options to the queue store' do
    allow(Karya::QueueStore::MySQL.send(:const_get, :Internal).const_get(:DependencyLoader)).to receive(:require_mysql2!).and_return(true)
    stub_const('Mysql2', Module.new) unless defined?(Mysql2)
    stub_const('Mysql2::Client', Class.new)
    allow(Mysql2::Client).to receive(:new).and_return(fake_connection)

    queue_store = described_class.new(
      url: 'mysql2://example.test/karya',
      namespace: 'payments',
      max_batch_size: 50
    ).build_queue_store

    expect(queue_store.send(:namespace)).to eq('payments')
    expect(queue_store.send(:max_batch_size)).to eq(50)
  end

  it 'normalizes invalid queue-store keyword errors into backend configuration errors' do
    allow(Karya::QueueStore::MySQL.send(:const_get, :Internal).const_get(:DependencyLoader)).to receive(:require_mysql2!).and_return(true)
    stub_const('Mysql2', Module.new) unless defined?(Mysql2)
    stub_const('Mysql2::Client', Class.new)
    allow(Mysql2::Client).to receive(:new).and_return(fake_connection)

    invalid_backend = described_class.new(
      url: 'mysql2://example.test/karya',
      namespace: 'payments',
      unsupported_option: true
    )

    expect do
      invalid_backend.build_queue_store
    end.to raise_error(
      Karya::InvalidBackendConfigurationError,
      /invalid MySQL backend queue-store configuration: unexpected option keys :unsupported_option: unknown keywords: unsupported_option/
    ) { |error| expect(error.cause).to be_a(ArgumentError) }
  end

  it 'normalizes queue-store validation failures into backend configuration errors' do
    invalid_backend = described_class.new(url: ' ', namespace: 'payments')

    expect do
      invalid_backend.build_queue_store
    end.to raise_error(
      Karya::InvalidBackendConfigurationError,
      /invalid MySQL backend queue-store configuration: url must be a non-empty String/
    ) { |error| expect(error.cause).to be_a(Karya::InvalidQueueStoreOperationError) }
  end

  it 'declares no-op lifecycle hooks around queue-store usage' do
    allow(Karya::QueueStore::MySQL.send(:const_get, :Internal).const_get(:DependencyLoader)).to receive(:require_mysql2!).and_return(true)
    stub_const('Mysql2', Module.new) unless defined?(Mysql2)
    stub_const('Mysql2::Client', Class.new)
    allow(Mysql2::Client).to receive(:new).and_return(fake_connection)
    queue_store = backend.build_queue_store

    expect(backend.before_start(queue_store:)).to be_nil
    expect(backend.after_stop(queue_store:)).to be_nil
  end

  def fake_connection
    @fake_connection ||= fake_connection_class.new
  end
end
