# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe Karya::Backend::Redis do
  subject(:backend) { described_class.new(url: 'redis://example.test:6379/0') }

  it 'loads as a standalone backend file' do
    lib_path = File.expand_path('../../../lib', __dir__)
    script = <<~RUBY
      require 'karya/backend/redis'
      puts Karya::Backend::Redis.new(url: 'redis://example.test:6379/0').identifier
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status.success?).to be(true), stderr
    expect(stdout).to eq("redis\n")
  end

  it 'loads Redis queue-store execution paths as a standalone file' do
    lib_path = File.expand_path('../../../lib', __dir__)
    script = <<~RUBY
      require 'karya/queue_store/redis'

      FakeRedis = Class.new do
        def initialize
          @data = {}
        end

        def get(key)
          @data[key]
        end

        def set(key, value, **options)
          if options.fetch(:nx, false)
            return nil if @data.key?(key)
          end

          @data[key] = value
          'OK'
        end

        def del(key)
          @data.delete(key) ? 1 : 0
        end

        def expire(key, _seconds)
          @data.key?(key) ? 1 : 0
        end

        def eval(_script, keys:, argv:)
          key = keys.fetch(0)
          token = argv.fetch(0)
          return 0 unless get(key) == token

          if keys.length == 2
            @data[keys.fetch(1)] = argv.fetch(1)
            1
          else
            del(key)
          end
        end
      end

      class << Redis
        alias_method :__karya_redis_spec_original_new, :new

        def new(url:)
          @__karya_fake_redis ||= FakeRedis.new
        end
      end

      now = Time.utc(2026, 5, 5, 12, 0, 0)
      store = Karya::QueueStore::Redis.new(url: 'redis://example.test:6379/0', namespace: 'standalone')
      job = Karya::Job.new(id: 'job-1', queue: 'billing', handler: 'billing_sync', state: :submission, created_at: now)
      store.enqueue(job:, now: now + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: now + 2)
      store.start_execution(reservation_token: reservation.token, now: now + 3)
      failed = store.fail_execution(reservation_token: reservation.token, now: now + 4, failure_classification: :error)
      puts failed.state
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status.success?).to be(true), stderr
    expect(stdout).to eq("failed\n")
  end

  it 'raises an actionable load error when the redis gem is not available' do
    lib_path = File.expand_path('../../../lib', __dir__)
    script = <<~RUBY
      module Kernel
        alias_method :__karya_original_require_for_redis_spec, :require

        def require(name)
          raise LoadError, 'cannot load such file -- redis' if name == 'redis'

          __karya_original_require_for_redis_spec(name)
        end
      end

      begin
        require 'karya/backend/redis'
      rescue LoadError => e
        warn e.message
        exit 0
      end

      exit 1
    RUBY

    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status.success?).to be(true)
    expect(stderr).to include("Add `gem 'redis', '~> 5.4'` to your Gemfile to use Karya::Backend::Redis and Karya::QueueStore::Redis.")
  end

  it 'exposes the backend identifier' do
    expect(backend.identifier).to eq('redis')
  end

  it 'builds the Redis queue store owned by the backend definition' do
    queue_store = backend.build_queue_store

    expect(queue_store).to be_a(Karya::QueueStore::Redis)
  end

  it 'forwards namespace and queue-store options to the queue store' do
    queue_store = described_class.new(
      url: 'redis://example.test:6379/0',
      namespace: 'payments',
      max_batch_size: 50
    ).build_queue_store

    expect(queue_store.send(:namespace)).to eq('payments')
    expect(queue_store.send(:max_batch_size)).to eq(50)
  end

  it 'normalizes invalid queue-store keyword errors into backend configuration errors' do
    backend = described_class.new(
      url: 'redis://example.test:6379/0',
      namespace: 'payments',
      unsupported_option: true
    )

    expect do
      backend.build_queue_store
    end.to raise_error(
      Karya::InvalidBackendConfigurationError,
      /invalid Redis backend queue-store configuration: unexpected option keys :unsupported_option: unknown keywords: unsupported_option/
    ) { |error| expect(error.cause).to be_a(ArgumentError) }
  end

  it 'normalizes valid-key queue-store construction failures into backend configuration errors' do
    allow(Karya::QueueStore::Redis).to receive(:new).and_raise(TypeError, 'coercion failure')

    expect do
      backend.build_queue_store
    end.to raise_error(
      Karya::InvalidBackendConfigurationError,
      /invalid Redis backend queue-store configuration: coercion failure/
    ) { |error| expect(error.cause).to be_a(TypeError) }
  end

  it 'normalizes queue-store validation failures into backend configuration errors' do
    backend = described_class.new(url: ' ', namespace: 'payments')

    expect do
      backend.build_queue_store
    end.to raise_error(
      Karya::InvalidBackendConfigurationError,
      /invalid Redis backend queue-store configuration: url must be a non-empty String/
    ) { |error| expect(error.cause).to be_a(Karya::InvalidQueueStoreOperationError) }
  end

  it 'declares no-op lifecycle hooks around queue-store usage' do
    queue_store = backend.build_queue_store

    expect(backend.before_start(queue_store:)).to be_nil
    expect(backend.after_stop(queue_store:)).to be_nil
  end
end
