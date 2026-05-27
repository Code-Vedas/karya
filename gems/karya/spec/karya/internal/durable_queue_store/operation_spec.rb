# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::Operation do
  it 'raises until subclasses implement call' do
    operation = described_class.new(store: Object.new, request: {}, operation_name: :enqueue)

    expect do
      operation.call(context: Object.new)
    end.to raise_error(NotImplementedError, /must implement #call/)
  end
end
