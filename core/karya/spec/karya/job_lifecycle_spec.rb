# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::JobLifecycle do
  around do |example|
    described_class.clear_extensions!
    example.run
    described_class.clear_extensions!
  end

  describe '.normalize_state' do
    it 'normalizes string and symbol states to canonical snake_case symbols' do
      expect(described_class.normalize_state('retry-pending')).to eq(:retry_pending)
      expect(described_class.normalize_state(' Queued ')).to eq(:queued)
      expect(described_class.normalize_state(:queued)).to eq(:queued)
    end

    it 'rejects unknown states' do
      expect { described_class.normalize_state(:unknown) }
        .to raise_error(Karya::InvalidJobStateError, /Unknown job state/)
    end

    it 'rejects blank states with a presence error' do
      expect { described_class.normalize_state(nil) }
        .to raise_error(Karya::InvalidJobStateError, /state must be present/)
      expect { described_class.normalize_state('   ') }
        .to raise_error(Karya::InvalidJobStateError, /state must be present/)
    end
  end

  describe '.valid_transition?' do
    it 'returns true for every allowed transition in the lifecycle table' do
      described_class::TRANSITIONS.each do |from_state, to_states|
        to_states.each do |to_state|
          expect(described_class.valid_transition?(from: from_state, to: to_state)).to be(true)
        end
      end
    end

    it 'returns false for disallowed transitions' do
      expect(described_class.valid_transition?(from: :queued, to: :running)).to be(false)
      expect(described_class.valid_transition?(from: :succeeded, to: :queued)).to be(false)
    end

    it 'rejects unknown states while validating transitions' do
      expect { described_class.valid_transition?(from: :queued, to: :unknown) }
        .to raise_error(Karya::InvalidJobStateError, /Unknown job state/)
    end
  end

  describe '.validate_transition!' do
    it 'returns the normalized target state for valid transitions' do
      expect(described_class.validate_transition!(from: :running, to: 'cancelled')).to eq(:cancelled)
      expect(described_class.validate_transition!(from: :failed, to: 'retry-pending')).to eq(:retry_pending)
    end

    it 'rejects invalid transitions' do
      expect { described_class.validate_transition!(from: :cancelled, to: :running) }
        .to raise_error(Karya::InvalidJobTransitionError, /Cannot transition/)
    end
  end

  describe 'extensions' do
    it 'allows later lifecycle states to be registered and linked to canonical states' do
      described_class.register_state(:dead_letter, terminal: true)
      described_class.register_transition(from: :retry_pending, to: :dead_letter)

      expect(described_class.normalize_state('dead-letter')).to eq(:dead_letter)
      expect(described_class.valid_transition?(from: :retry_pending, to: :dead_letter)).to be(true)
      expect(described_class.terminal?(:dead_letter)).to be(true)
    end

    it 'rejects duplicate extension state registration' do
      described_class.register_state(:dead_letter)

      expect { described_class.register_state(:dead_letter) }
        .to raise_error(Karya::InvalidJobStateError, /state must be new/)
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
