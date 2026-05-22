# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::DuplicateKeySummary do
  it 'renders short keys without truncation' do
    expect(described_class.new('abc').to_s).to eq('"abc" (length=3)')
  end

  it 'truncates long keys to the preview limit' do
    long_key = 'x' * 70
    preview = 'x' * 64

    expect(described_class.new(long_key).to_s).to eq(%("#{preview}..." (length=70)))
  end
end
