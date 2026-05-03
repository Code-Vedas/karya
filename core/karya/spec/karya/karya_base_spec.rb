# frozen_string_literal: true

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
      options = { queue_store_class: Karya::QueueStore::InMemory, enabled: true }

      expect(
        described_class.configure_backend(backend_class, **options)
      ).to be(backend_class)
      expect(described_class.backend_class).to be(backend_class)
      expect(described_class.backend_options).to eq(options)
    end

    it 'returns a defensive copy of backend options' do
      described_class.configure_backend(Karya::Backend::InMemory, queue_store_class: Karya::QueueStore::InMemory)

      first_read = described_class.backend_options
      second_read = described_class.backend_options
      first_read[:queue_store_class] = Object

      expect(second_read).to eq(queue_store_class: Karya::QueueStore::InMemory)
      expect(described_class.backend_options).to eq(queue_store_class: Karya::QueueStore::InMemory)
    end

    it 'rejects a configured backend that does not respond to .new' do
      expect do
        described_class.configure_backend(Object.new)
      end.to raise_error(Karya::InvalidBackendConfigurationError, /must respond to \.new/)
    end

    it 'rejects nil as a configured backend class' do
      expect do
        described_class.configure_backend(nil)
      end.to raise_error(Karya::InvalidBackendConfigurationError, /must respond to \.new/)
    end

    it 'returns nil and an empty options hash when no backend is configured' do
      described_class.remove_instance_variable(:@backend_class) if described_class.instance_variable_defined?(:@backend_class)
      described_class.remove_instance_variable(:@backend_options) if described_class.instance_variable_defined?(:@backend_options)

      expect(described_class.backend_class).to be_nil
      expect(described_class.backend_options).to eq({})
    end
  end
end
