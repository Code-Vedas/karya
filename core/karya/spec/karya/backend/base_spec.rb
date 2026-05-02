# frozen_string_literal: true

RSpec.describe Karya::Backend::Base do
  subject(:backend) { implementation.new }

  let(:implementation) do
    Class.new do
      include Karya::Backend::Base
    end
  end

  it 'requires descriptor to be implemented' do
    expect { backend.descriptor }.to raise_error(NotImplementedError, /implement #descriptor/)
  end

  it 'requires build_queue_store to be implemented' do
    expect { backend.build_queue_store }.to raise_error(NotImplementedError, /implement #build_queue_store/)
  end

  it 'provides no-op lifecycle hooks by default' do
    queue_store = instance_double(Karya::QueueStore::Base)

    expect(backend.before_start(queue_store:)).to be_nil
    expect(backend.after_stop(queue_store:)).to be_nil
  end

  it 'delegates identifier, classification, and capabilities through the descriptor' do
    capabilities = instance_double(Karya::Backend::Capabilities)
    descriptor = instance_double(
      Karya::Backend::Descriptor,
      identifier: 'in_memory',
      classification: :quick_setup_and_run,
      capabilities:
    )
    backend_class = Class.new do
      include Karya::Backend::Base

      define_method(:descriptor) { descriptor }
    end

    delegating_backend = backend_class.new

    expect(delegating_backend.identifier).to eq('in_memory')
    expect(delegating_backend.classification).to eq(:quick_setup_and_run)
    expect(delegating_backend.capabilities).to be(capabilities)
  end
end
