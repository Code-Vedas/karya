# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'open3'
require 'rbconfig'
require 'kaal'

RSpec.describe Karya do
  describe '.configure_backend' do
    around do |example|
      original_backend_class = described_class.instance_variable_get(:@backend_class)
      original_backend_class_defined = described_class.instance_variable_defined?(:@backend_class)
      original_backend_options = described_class.instance_variable_get(:@backend_options)
      original_backend_options_defined = described_class.instance_variable_defined?(:@backend_options)
      original_kaal_backend = Kaal.configuration.backend

      example.run
    ensure
      if original_backend_class_defined
        described_class.instance_variable_set(:@backend_class, original_backend_class)
      elsif described_class.instance_variable_defined?(:@backend_class)
        described_class.remove_instance_variable(:@backend_class)
      end

      if original_backend_options_defined
        described_class.instance_variable_set(:@backend_options, original_backend_options)
      elsif described_class.instance_variable_defined?(:@backend_options)
        described_class.remove_instance_variable(:@backend_options)
      end

      Kaal.reset_configuration!
      Kaal.configuration.backend = original_kaal_backend
    end

    it 'stores the configured backend class and backend options' do
      backend_class = Karya::Backend::InMemory
      options = { adapter_class: String, enabled: true }

      expect(
        described_class.configure_backend(backend_class, **options)
      ).to be(backend_class)
      expect(described_class.backend_class).to be(backend_class)
      expect(described_class.backend_options).to eq(options)
      expect(Kaal.configuration.backend).to be_a(Kaal::Backend::MemoryAdapter)
    end

    it 'does not overwrite an explicit Kaal backend while configuring Karya' do
      explicit_backend = Kaal::Backend::MemoryAdapter.new
      Kaal.configuration.backend = explicit_backend

      described_class.configure_backend(Karya::Backend::InMemory)

      expect(Kaal.configuration.backend).to eq(explicit_backend)
    end

    it 'keeps backend configuration working when optional Kaal dependencies are unavailable' do
      allow(Karya::Internal::KaalBackendMapper).to receive(:synchronize!).and_raise(LoadError, 'cannot load such file -- kaal')

      expect(
        described_class.configure_backend(Karya::Backend::InMemory)
      ).to be(Karya::Backend::InMemory)
      expect(described_class.backend_class).to be(Karya::Backend::InMemory)
    end

    it 'returns a defensive copy of backend options' do
      described_class.configure_backend(Karya::Backend::InMemory, adapter_class: String)

      first_read = described_class.backend_options
      second_read = described_class.backend_options
      first_read[:adapter_class] = Object

      expect(second_read).to eq(adapter_class: String)
      expect(described_class.backend_options).to eq(adapter_class: String)
    end

    it 'snapshots nested backend options immutably' do
      flags = [true, :local]
      metadata = { adapter: 'in_memory', flags: }
      described_class.configure_backend(Karya::Backend::InMemory, metadata:)

      flags << :mutated
      metadata[:adapter] = 'changed'
      first_read = described_class.backend_options
      first_read[:metadata][:flags] << :changed
      first_read[:metadata][:adapter] = 'modified'

      expect(described_class.backend_options).to eq(
        metadata: {
          adapter: 'in_memory',
          flags: [true, :local]
        }
      )
    end

    it 'snapshots nested string values and string keys immutably' do
      adapter = +'in_memory'
      key = +'adapter'
      metadata = { key => adapter }

      described_class.configure_backend(Karya::Backend::InMemory, metadata:)

      key << '_changed'
      adapter << '_changed'

      first_read = described_class.backend_options
      second_read = described_class.backend_options
      first_read[:metadata]['adapter'] << '_mutated'
      first_read[:metadata]['adapter'] = 'rewritten'
      first_read[:metadata]['new_key'] = 'value'

      expect(second_read).to eq(metadata: { 'adapter' => 'in_memory' })
      expect(described_class.backend_options).to eq(metadata: { 'adapter' => 'in_memory' })
    end

    it 'accepts nested backend options built from supported values' do
      options = {
        token_generator: -> { 'token' },
        policy_set: Karya::Backpressure::PolicySet.new,
        circuit_breaker_policy_set: Karya::CircuitBreaker::PolicySet.new,
        fairness_policy: Karya::Fairness::Policy.new,
        metadata: {
          adapter: 'in_memory',
          flags: [true, :local]
        }
      }

      described_class.configure_backend(Karya::Backend::InMemory, **options)

      expect(described_class.backend_options).to eq(options)
    end

    it 'does not apply top-level queue_store_class special-casing to nested metadata' do
      callable = Object.new
      callable.define_singleton_method(:call) { 'token' }

      described_class.configure_backend(
        Karya::Backend::InMemory,
        metadata: { queue_store_class: callable }
      )

      expect(described_class.backend_options).to eq(metadata: { queue_store_class: callable })
    end

    it 'accepts generic callable backend option values' do
      callable = Object.new
      callable.define_singleton_method(:call) { 'token' }

      described_class.configure_backend(Karya::Backend::InMemory, token_generator: callable)

      expect(described_class.backend_options).to eq(token_generator: callable)
    end

    it 'accepts class-valued backend options outside queue_store_class' do
      described_class.configure_backend(Karya::Backend::InMemory, adapter_class: String)

      expect(described_class.backend_options).to eq(adapter_class: String)
    end

    it 'accepts queue store instances when a backend class owns that option' do
      queue_store = Karya::QueueStore::InMemory.new

      described_class.configure_backend(Karya::Backend::InMemory, queue_store:)

      expect(described_class.backend_options).to eq(queue_store:)
    end

    it 'rejects non-callable backend options that are not queue store factories' do
      expect do
        described_class.configure_backend(Karya::Backend::InMemory, token_generator: Object.new)
      end.to raise_error(Karya::InvalidBackendConfigurationError, /unsupported value/)
    end

    it 'rejects a configured backend that does not respond to .new' do
      expect do
        described_class.configure_backend(Object.new)
      end.to raise_error(Karya::InvalidBackendConfigurationError, /must be a Class/)
    end

    it 'rejects nil as a configured backend class' do
      expect do
        described_class.configure_backend(nil)
      end.to raise_error(Karya::InvalidBackendConfigurationError, /must be a Class/)
    end

    it 'rejects configured backend classes that do not include the backend contract' do
      backend_class = Class.new

      expect do
        described_class.configure_backend(backend_class)
      end.to raise_error(Karya::InvalidBackendConfigurationError, /must include Karya::Backend::Base/)
    end

    it 'accepts a configured backend class that overrides .new' do
      backend_class = Class.new do
        include Karya::Backend::Base

        define_singleton_method(:new) do |**|
          super
        end

        def identifier
          'test_backend'
        end

        def build_queue_store
          Karya::QueueStore::InMemory.new
        end
      end

      expect(described_class.configure_backend(backend_class)).to be(backend_class)
    end

    it 'rejects a configured backend option with an unsupported value' do
      expect do
        described_class.configure_backend(Karya::Backend::InMemory, adapter_class: Object.new)
      end.to raise_error(Karya::InvalidBackendConfigurationError, /unsupported value/)
    end

    it 'rejects a configured backend option with a non-symbol top-level key' do
      described_class.instance_variable_set(:@backend_class, Karya::Backend::InMemory)
      described_class.instance_variable_set(:@backend_options, { 'adapter_class' => String })

      expect do
        described_class.backend_options
      end.to raise_error(Karya::InvalidBackendConfigurationError, /option keys must be Symbols/)
    end

    it 'rejects corrupted backend options that are not a hash' do
      described_class.instance_variable_set(:@backend_class, Karya::Backend::InMemory)
      described_class.instance_variable_set(:@backend_options, %w[not a hash])

      expect do
        described_class.backend_options
      end.to raise_error(Karya::InvalidBackendConfigurationError, /options must be a Hash/)
    end

    it 'returns nil and an empty options hash when no backend is configured' do
      described_class.remove_instance_variable(:@backend_class) if described_class.instance_variable_defined?(:@backend_class)
      described_class.remove_instance_variable(:@backend_options) if described_class.instance_variable_defined?(:@backend_options)

      expect(described_class.backend_class).to be_nil
      expect(described_class.backend_options).to eq({})
    end

    it 'rejects corrupted backend class state when reading it back' do
      described_class.instance_variable_set(:@backend_class, Object.new)

      expect do
        described_class.backend_class
      end.to raise_error(Karya::InvalidBackendConfigurationError, /must be a Class/)
    end

    it 'rejects corrupted backend class state that no longer includes the backend contract' do
      described_class.instance_variable_set(:@backend_class, Class.new)

      expect do
        described_class.backend_class
      end.to raise_error(Karya::InvalidBackendConfigurationError, /must include Karya::Backend::Base/)
    end

    it 'loads backend support when karya/base is required directly' do
      lib_path = File.expand_path('../../../lib', __dir__)
      script = <<~RUBY
        require 'karya/base'
        require 'karya/backend/base'

        backend_class = Class.new do
          include Karya::Backend::Base

          def identifier = 'direct_base_backend'
          def build_queue_store = nil
        end

        Karya.configure_backend(backend_class)
        puts Karya.backend_class == backend_class
      RUBY

      stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

      expect(status.success?).to be(true), stderr
      expect(stdout).to eq("true\n")
    end
  end

  describe '.generic_backend_option?' do
    it 'treats queue_store_class like any other generic callable option' do
      callable = Object.new
      callable.define_singleton_method(:call) { Karya::QueueStore::InMemory.new }

      expect(
        described_class.send(:generic_backend_option?, :queue_store_class, callable)
      ).to be(true)
    end
  end

  describe '.configure_operator_authorizer' do
    around do |example|
      original_authorizer = described_class.operator_authorizer if described_class.instance_variable_defined?(:@operator_authorizer)

      example.run
    ensure
      described_class.configure_operator_authorizer(original_authorizer)
    end

    it 'stores, clears, and exposes the configured process-wide operator authorizer' do
      authorizer = ->(_request_context) { true }

      expect(described_class.configure_operator_authorizer(authorizer)).to eq(authorizer)
      expect(described_class.operator_authorizer).to eq(authorizer)
      expect(described_class.configure_operator_authorizer(nil)).to be_nil
      expect(described_class.operator_authorizer).to be_nil
    end

    it 'rejects non-callable process-wide operator authorizers' do
      expect do
        described_class.configure_operator_authorizer(Object.new)
      end.to raise_error(ArgumentError, 'operator authorizer must respond to #call')
    end
  end

  describe '.enqueue and .enqueue_at' do
    around do |example|
      original_backend_class_defined = described_class.instance_variable_defined?(:@backend_class)
      original_backend_class = described_class.instance_variable_get(:@backend_class)
      original_backend_options_defined = described_class.instance_variable_defined?(:@backend_options)
      original_backend_options = described_class.instance_variable_get(:@backend_options)
      original_queue_store_defined = described_class.instance_variable_defined?(:@queue_store)
      original_queue_store = described_class.instance_variable_get(:@queue_store)
      original_kaal_backend = Kaal.configuration.backend
      original_delayed_job_allowed_class_prefixes = Kaal.configuration.delayed_job_allowed_class_prefixes
      Karya::FrameworkRuntime.reset_shared_runtime!
      example.run
    ensure
      Karya::FrameworkRuntime.reset_shared_runtime!
      restore_instance_variable(:@backend_class, original_backend_class_defined, original_backend_class)
      restore_instance_variable(:@backend_options, original_backend_options_defined, original_backend_options)
      restore_instance_variable(:@queue_store, original_queue_store_defined, original_queue_store)
      Kaal.reset_configuration!
      Kaal.configuration.backend = original_kaal_backend
      Kaal.configuration.delayed_job_allowed_class_prefixes = original_delayed_job_allowed_class_prefixes
    end

    it 'enqueues through the configured queue store' do
      queue_store = instance_double(Karya::QueueStore::Base)
      enqueue_calls = []
      allow(queue_store).to receive(:enqueue) { |job:, now:| enqueue_calls << [job, now] }
      described_class.configure_queue_store(queue_store)

      job = described_class.enqueue(
        queue: 'critical',
        handler: 'email_sender',
        arguments: { account_id: 7 },
        now: Time.utc(2026, 5, 21, 12, 0, 0),
        job_id: 'job-1'
      )

      expect(job.id).to eq('job-1')
      expect(job.queue).to eq('critical')
      expect(job.handler).to eq('email_sender')
      expect(job.arguments).to eq('account_id' => 7)
      expect(enqueue_calls.fetch(0).fetch(0)).to eq(job)
    end

    it 'uses the shared runtime queue store when no queue store is preconfigured' do
      queue_store = instance_double(Karya::QueueStore::Base, enqueue: nil)
      shared_runtime = instance_double(Karya::FrameworkRuntime::HostRuntime, queue_store:)
      backend_class = Class.new do
        include Karya::Backend::Base

        def initialize(**) = nil
        def identifier = 'sqlite'
      end
      allow(Karya::FrameworkRuntime).to receive(:shared_runtime).and_return(shared_runtime)
      described_class.remove_instance_variable(:@queue_store) if described_class.instance_variable_defined?(:@queue_store)
      described_class.configure_backend(
        backend_class,
        url: 'sqlite3:///tmp/base-enqueue-spec.sqlite3',
        namespace: 'base-enqueue-spec'
      )

      described_class.enqueue(queue: 'default', handler: 'demo', arguments: {}, job_id: 'job-2')

      expect(Karya::FrameworkRuntime).to have_received(:shared_runtime).with(
        backend_class:,
        backend_options: {
          url: 'sqlite3:///tmp/base-enqueue-spec.sqlite3',
          namespace: 'base-enqueue-spec'
        }
      )
      expect(queue_store).to have_received(:enqueue)
    end

    it 'uses the current runtime queue store when one is already started' do
      queue_store = instance_double(Karya::QueueStore::Base, enqueue: nil)
      runtime = instance_double(Karya::FrameworkRuntime::HostRuntime, queue_store:)
      allow(Karya::FrameworkRuntime).to receive(:current_runtime).and_return(runtime)
      allow(Karya::FrameworkRuntime).to receive(:shared_runtime)
      described_class.remove_instance_variable(:@queue_store) if described_class.instance_variable_defined?(:@queue_store)

      described_class.enqueue(queue: 'default', handler: 'demo', arguments: {}, job_id: 'job-2b')

      expect(Karya::FrameworkRuntime).not_to have_received(:shared_runtime)
      expect(queue_store).to have_received(:enqueue)
    end

    it 'raises when neither a queue store nor backend is configured' do
      described_class.instance_variable_set(:@backend_class, nil)
      described_class.instance_variable_set(:@backend_options, {})
      described_class.instance_variable_set(:@queue_store, nil)

      expect do
        described_class.enqueue(queue: 'default', handler: 'demo', arguments: {}, job_id: 'job-3')
      end.to raise_error(Karya::MissingQueueStoreConfigurationError, 'Karya backend must be configured before enqueuing jobs')
    end

    it 'raises for future jobs when Kaal delayed enqueue is unavailable and enqueues past jobs immediately' do
      Kaal.reset_configuration!
      scheduled_at = Time.utc(2026, 5, 21, 12, 5, 1)

      expect do
        described_class.enqueue_at(
          queue: 'default',
          handler: 'demo',
          arguments: { task: 'later' },
          at: scheduled_at,
          now: Time.utc(2026, 5, 21, 12, 0, 0),
          job_id: 'future-job'
        )
      end.to raise_error(Karya::UnsupportedSchedulingError, /#{Regexp.escape(scheduled_at.to_s)}/)

      queue_store = instance_double(Karya::QueueStore::Base, enqueue: nil)
      described_class.configure_queue_store(queue_store)
      immediate_job = described_class.enqueue_at(
        queue: 'default',
        handler: 'demo',
        arguments: { task: 'now' },
        at: Time.utc(2026, 5, 21, 11, 59, 59),
        now: Time.utc(2026, 5, 21, 12, 0, 0),
        job_id: 'immediate-job'
      )

      expect(immediate_job).to be_a(Karya::Job)
      expect(queue_store).to have_received(:enqueue)
    end

    it 'keeps exact-minute schedule times unchanged before rejecting them' do
      Kaal.reset_configuration!

      expect do
        described_class.enqueue_at(
          queue: 'default',
          handler: 'demo',
          arguments: { task: 'later' },
          at: Time.utc(2026, 5, 21, 12, 6, 0),
          now: Time.utc(2026, 5, 21, 12, 0, 0),
          job_id: 'future-job-on-minute'
        )
      end.to raise_error(
        Karya::UnsupportedSchedulingError,
        /2026-05-21 12:06:00 UTC/
      )
    end

    it 'delegates future jobs to Kaal through the internal delayed wrapper' do
      Kaal.reset_configuration!
      Kaal.configuration.backend = Kaal::Backend::MemoryAdapter.new
      scheduled_at = Time.utc(2026, 5, 21, 12, 5, 1)

      receipt = described_class.enqueue_at(
        queue: 'default',
        handler: 'demo',
        arguments: { task: 'later', requested_at: Time.utc(2026, 5, 21, 11, 59, 0) },
        at: scheduled_at,
        now: Time.utc(2026, 5, 21, 12, 0, 0),
        job_id: 'future-job'
      )

      expect(receipt).to include(
        job_id: 'future-job',
        job_class: 'Karya::Internal::DelayedEnqueueJob',
        queue: nil,
        run_at: scheduled_at
      )

      payload = Karya::Internal::DelayedEnqueueJob.deserialize_request(receipt.fetch(:args).fetch(0))
      expect(payload).to include(
        'queue' => 'default',
        'handler' => 'demo',
        'job_id' => 'future-job',
        'arguments' => { 'task' => 'later', 'requested_at' => Time.utc(2026, 5, 21, 11, 59, 0) },
        'created_at' => Time.utc(2026, 5, 21, 12, 0, 0),
        'scheduled_at' => scheduled_at
      )
    end

    it 'preserves sub-second schedule times when delegating future jobs to Kaal' do
      Kaal.reset_configuration!
      Kaal.configuration.backend = Kaal::Backend::MemoryAdapter.new
      scheduled_at = Time.utc(2026, 5, 21, 12, 5, 1) + Rational(123_456_789, 1_000_000_000)

      receipt = described_class.enqueue_at(
        queue: 'default',
        handler: 'demo',
        arguments: { task: 'later' },
        at: scheduled_at,
        now: Time.utc(2026, 5, 21, 12, 0, 0),
        job_id: 'future-job-subsecond'
      )

      expect(receipt.fetch(:run_at)).to eq(scheduled_at)
      payload = Karya::Internal::DelayedEnqueueJob.deserialize_request(receipt.fetch(:args).fetch(0))
      expect(payload.fetch('scheduled_at')).to eq(scheduled_at)
    end

    it 'surfaces Kaal delayed-job allow-list failures as unsupported scheduling' do
      Kaal.reset_configuration!
      Kaal.configuration.backend = Kaal::Backend::MemoryAdapter.new
      Kaal.configuration.delayed_job_allowed_class_prefixes = ['Other::']

      expect do
        described_class.enqueue_at(
          queue: 'default',
          handler: 'demo',
          arguments: { task: 'later' },
          at: Time.utc(2026, 5, 21, 12, 5, 1),
          now: Time.utc(2026, 5, 21, 12, 0, 0),
          job_id: 'future-job'
        )
      end.to raise_error(Karya::UnsupportedSchedulingError, /not allowed/)
    end

    it 'accepts numeric enqueue times' do
      queue_store = instance_double(Karya::QueueStore::Base, enqueue: nil)
      described_class.configure_queue_store(queue_store)

      job = described_class.enqueue(
        queue: 'default',
        handler: 'demo',
        arguments: {},
        now: Time.utc(2026, 5, 21, 12, 0, 0).to_f,
        job_id: 'numeric-now-job'
      )

      expect(job.created_at).to eq(Time.utc(2026, 5, 21, 12, 0, 0))
      expect(job.enqueued_at).to eq(Time.utc(2026, 5, 21, 12, 0, 0))
      expect(queue_store).to have_received(:enqueue)
    end
  end

  def restore_instance_variable(name, defined, value)
    return Karya.instance_variable_set(name, value) if defined
    return unless Karya.instance_variable_defined?(name)

    Karya.remove_instance_variable(name)
  end
end
