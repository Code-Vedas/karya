# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::ImmutableArgumentGraph do
  let(:error_class) { ArgumentError }

  describe '#normalize' do
    it 'returns already-normalized hash as-is' do
      normalized = { 'key' => 'value' }.freeze

      result = described_class.new(normalized, error_class:).normalize

      expect(result).to be(normalized)
    end

    it 'does not duplicate already-frozen duplicable scalars' do
      frozen_name = 'Alice'
      frozen_time = Time.utc(2026, 4, 24).freeze

      result = described_class.new({ 'name' => frozen_name, 'time' => frozen_time }, error_class:).normalize

      expect(result['name']).to be(frozen_name)
      expect(result['time']).to be(frozen_time)
    end
  end
end
