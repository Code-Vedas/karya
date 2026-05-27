# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../../lib/karya/internal/dead_letter_reason'

RSpec.describe Karya::Internal::DeadLetterReason do
  it 'strips and freezes normalized reasons' do
    reason = described_class.normalize("  poison job  \n", error_class: Karya::InvalidQueueStoreOperationError)

    expect(reason).to eq('poison job')
    expect(reason).to be_frozen
  end

  it 'rejects blank reasons' do
    expect do
      described_class.normalize(" \t ", error_class: Karya::InvalidQueueStoreOperationError)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /dead_letter_reason must be present/)
  end

  it 'rejects non-string reasons' do
    expect do
      described_class.normalize(:poison, error_class: Karya::InvalidQueueStoreOperationError)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /dead_letter_reason must be a String/)
  end
end
