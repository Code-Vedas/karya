# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

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
