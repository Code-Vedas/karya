# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe Karya do
  describe '.configure_backend' do
    around do |example|
      original_backend_class = described_class.instance_variable_get(:@backend_class)
      original_backend_class_defined = described_class.instance_variable_defined?(:@backend_class)
      original_backend_options = described_class.instance_variable_get(:@backend_options)
      original_backend_options_defined = described_class.instance_variable_defined?(:@backend_options)

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
    end

    it 'stores the configured backend class and backend options' do
      backend_class = Karya::Backend::InMemory
      options = { adapter_class: String, enabled: true }

      expect(
        described_class.configure_backend(backend_class, **options)
      ).to be(backend_class)
      expect(described_class.backend_class).to be(backend_class)
      expect(described_class.backend_options).to eq(options)
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
end
