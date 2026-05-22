# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../../../lib/karya/internal/runtime_support/signal_restorer'

RSpec.describe Karya::Internal::RuntimeSupport::SignalRestorer do
  it 'returns callable restorers unchanged' do
    restorer = -> {}

    expect(
      described_class.new(
        restorer,
        error_class: Karya::InvalidQueueStoreOperationError,
        message: 'signal_restorer must respond to #call'
      ).normalize
    ).to eq(restorer)
  end

  it 'rejects non-callable restorers' do
    expect do
      described_class.new(
        Object.new,
        error_class: Karya::InvalidQueueStoreOperationError,
        message: 'signal_restorer must respond to #call'
      ).normalize
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'signal_restorer must respond to #call')
  end
end
