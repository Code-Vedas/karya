# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::JobLifecycle do
  around do |example|
    described_class.send(:clear_extensions!)
    example.run
    described_class.send(:clear_extensions!)
  end

  describe '.states' do
    it 'returns the canonical states and registered extensions' do
      expect(described_class.states).to include(:queued, :retry_pending)

      described_class.register_state(:dead_letter)

      expect(described_class.states).to include('dead_letter')
    end
  end

  describe '.terminal_states' do
    it 'returns canonical and extension terminal states' do
      expect(described_class.terminal_states).to include(:succeeded, :cancelled)

      described_class.register_state(:dead_letter, terminal: true)

      expect(described_class.terminal_states).to include('dead_letter')
    end
  end

  describe '.terminal?' do
    it 'returns true for terminal states' do
      expect(described_class.terminal?(:succeeded)).to be(true)
      expect(described_class.terminal?('cancelled')).to be(true)
    end

    it 'returns false for non-terminal states' do
      expect(described_class.terminal?(:queued)).to be(false)
      expect(described_class.terminal?(:failed)).to be(false)
    end
  end
end
