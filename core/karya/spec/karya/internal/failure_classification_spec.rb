# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::FailureClassification do
  describe '.normalize' do
    it 'normalizes supported string input to the canonical symbol' do
      expect(described_class.normalize('timeout', error_class: Karya::InvalidJobAttributeError)).to eq(:timeout)
    end

    it 'does not expose a top-level Karya::FailureClassification helper' do
      expect(Karya.const_defined?(:FailureClassification, false)).to be(false)
    end
  end
end
