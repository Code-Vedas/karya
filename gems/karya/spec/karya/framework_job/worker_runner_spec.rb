# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::FrameworkJob::WorkerRunner do
  let(:queue_store) { Karya::QueueStore::InMemory.new(token_generator: -> { 'lease-token' }) }

  around do |example|
    original_backend_class = Karya.instance_variable_get(:@backend_class)
    original_backend_options = Karya.instance_variable_get(:@backend_options)
    original_queue_store = Karya.instance_variable_get(:@queue_store)
    Karya.instance_variable_set(:@backend_class, nil)
    Karya.instance_variable_set(:@backend_options, {})
    Karya.configure_queue_store(queue_store)
    example.run
  ensure
    Karya.instance_variable_set(:@backend_class, original_backend_class)
    Karya.instance_variable_set(:@backend_options, original_backend_options)
    Karya.configure_queue_store(original_queue_store)
  end

  it 'runs the worker supervisor with the configured queue store when no backend class is set' do
    supervisor = instance_double(Karya::WorkerSupervisor, run: :ok)
    allow(Karya::WorkerSupervisor).to receive(:new).and_return(supervisor)

    result = described_class.run(queues: ['billing'], handlers: { 'BillingSyncJob' => Class.new })

    expect(result).to eq(:ok)
    expect(Karya::WorkerSupervisor).to have_received(:new).with(
      hash_including(queue_store:, queues: ['billing'], handlers: { 'BillingSyncJob' => kind_of(Class) })
    )
  end

  it 'starts and stops a configured backend around the worker supervisor' do
    backend_class = Class.new do
      include Karya::Backend::Base

      attr_reader :events

      def initialize
        @events = []
      end

      def identifier = 'test'

      def build_queue_store
        Karya::QueueStore::InMemory.new(token_generator: -> { 'lease-token' })
      end

      def before_start(queue_store:)
        events << [:before_start, queue_store.class.name]
      end

      def after_stop(queue_store:)
        events << [:after_stop, queue_store.class.name]
      end
    end
    Karya.configure_backend(backend_class)
    supervisor = instance_double(Karya::WorkerSupervisor, run: :ok)
    allow(Karya::WorkerSupervisor).to receive(:new).and_return(supervisor)

    described_class.run(queues: ['billing'], handlers: { 'BillingSyncJob' => Class.new })

    expect(Karya::WorkerSupervisor).to have_received(:new)
  end

  it 'validates backend and queue store contracts' do
    invalid_backend_class = Class.new do
      def initialize(**); end
    end
    Karya.instance_variable_set(:@backend_class, invalid_backend_class)
    Karya.instance_variable_set(:@backend_options, {})

    expect do
      described_class.instantiate_backend
    end.to raise_error(Karya::InvalidBackendConfigurationError, /must include Karya::Backend::Base/)

    backend_class = Class.new do
      include Karya::Backend::Base

      def identifier = 'test'
      def build_queue_store = Object.new
    end
    backend = backend_class.new

    expect do
      described_class.build_queue_store(backend)
    end.to raise_error(Karya::InvalidBackendConfigurationError, /must build a Karya::QueueStore::Base/)

    invalid_runtime_backend_class = Class.new do
      include Karya::Backend::Base

      def identifier = 'invalid'
      def build_queue_store = queue_store
    end
    Karya.instance_variable_set(:@backend_class, invalid_runtime_backend_class)
    Karya.instance_variable_set(:@backend_options, {})
    allow(invalid_runtime_backend_class).to receive(:new).and_return(Object.new)

    expect do
      described_class.instantiate_backend
    end.to raise_error(Karya::InvalidBackendConfigurationError, /must instantiate a backend including/)

    exploding_backend_class = Class.new do
      include Karya::Backend::Base

      def self.new(**)
        raise ArgumentError, 'boom'
      end
    end
    Karya.instance_variable_set(:@backend_class, exploding_backend_class)

    expect do
      described_class.instantiate_backend
    end.to raise_error(Karya::InvalidBackendConfigurationError, /could not be initialized: boom/)
  end

  it 'validates queues and preserves cleanup when after_stop raises' do
    backend = Object.new
    backend.define_singleton_method(:before_start) { |queue_store:| queue_store }
    backend.define_singleton_method(:after_stop) { |**| raise 'boom' }

    expect do
      described_class.normalize_queues('billing')
    end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /queues must be an Array/)

    expect { described_class.safe_after_stop(backend, queue_store) }.not_to raise_error
    expect { described_class.safe_after_stop(nil, queue_store) }.not_to raise_error

    expect do
      described_class.run_with_lifecycle(backend, queue_store) { raise 'run failure' }
    end.to raise_error('run failure')
  end
end
