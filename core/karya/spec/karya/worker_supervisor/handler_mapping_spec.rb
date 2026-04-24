# frozen_string_literal: true

RSpec.describe 'Karya::WorkerSupervisor::HandlerMapping' do
  let(:handler_mapping_class) { Karya::WorkerSupervisor.const_get(:HandlerMapping, false) }
  let(:handler) { -> {} }

  it 'normalizes handler names into a frozen hash' do
    mapping = handler_mapping_class.new({ billing_sync: handler }).normalize

    expect(mapping).to eq({ 'billing_sync' => handler })
    expect(mapping).to be_frozen
  end

  it 'rejects empty handler maps' do
    expect do
      handler_mapping_class.new({}).normalize
    end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, 'handlers must be present')
  end
end
