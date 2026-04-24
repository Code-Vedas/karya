# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../../../lib/karya/internal/runtime_support/iteration_limit'

RSpec.describe Karya::Internal::RuntimeSupport::IterationLimit do
  it 'treats nil as the unlimited sentinel' do
    limit = described_class.new(nil, error_class: Karya::InvalidQueueStoreOperationError)

    expect(limit.normalize).to eq(:unlimited)
    expect(limit.reached?(10)).to be(false)
  end

  it 'tracks positive integer iteration limits' do
    limit = described_class.new(3, error_class: Karya::InvalidQueueStoreOperationError)

    expect(limit.normalize).to eq(3)
    expect(limit.reached?(2)).to be(false)
    expect(limit.reached?(3)).to be(true)
  end

  it 'rejects non-positive iteration limits' do
    expect do
      described_class.new(0, error_class: Karya::InvalidQueueStoreOperationError).normalize
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /max_iterations must be a positive Integer/)
  end
end
