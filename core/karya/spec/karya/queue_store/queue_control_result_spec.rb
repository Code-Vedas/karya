# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::QueueControlResult do
  let(:performed_at) { Time.utc(2026, 4, 1, 12, 0, 0) }

  def build_result(**overrides)
    described_class.new(action: :pause_queue, performed_at:, queue: 'billing', paused: true, changed: true, **overrides)
  end

  it 'freezes normalized queue control fields' do
    result = build_result

    expect(result).to have_attributes(action: :pause_queue, performed_at:, queue: 'billing', paused: true, changed: true)
    expect(result).to be_frozen
    expect(result.performed_at).to be_frozen
  end

  it 'validates constructor inputs' do
    expect { build_result(action: 'pause_queue') }.to raise_error(Karya::InvalidQueueStoreOperationError, /action/)
    expect { build_result(performed_at: 'now') }.to raise_error(Karya::InvalidQueueStoreOperationError, /performed_at/)
    expect { build_result(queue: :billing) }.to raise_error(Karya::InvalidQueueStoreOperationError, /queue/)
    expect { build_result(paused: nil) }.to raise_error(Karya::InvalidQueueStoreOperationError, /paused/)
    expect { build_result(changed: nil) }.to raise_error(Karya::InvalidQueueStoreOperationError, /changed/)
  end
end
