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
        .to raise_error(Karya::JobLifecycle::InvalidJobStateError, /Unknown job state/)
    end
  end

  describe '.transitions' do
    it 'returns frozen transition arrays for canonical states' do
      transition_map = described_class.transitions

      expect(transition_map).to be_frozen
      expect(transition_map[:queued]).to be_frozen
      expect { transition_map[:queued] << :running }.to raise_error(FrozenError)
    end

    it 'reuses the cached transition map until extensions change' do
      initial_transitions = described_class.transitions

      expect(described_class.transitions).to eq(initial_transitions)

      described_class.register_state(:quarantine, terminal: true)
      described_class.register_transition(from: :retry_pending, to: :quarantine)

      expect(described_class.transitions).not_to eq(initial_transitions)
    end

    it 'includes empty transition arrays for extension states without outgoing transitions' do
      described_class.register_state(:quarantine)

      transition_map = described_class.transitions

      expect(transition_map).to include('quarantine' => [])
      expect(transition_map['quarantine']).to be_frozen
    end
  end

  describe '.validate_transition!' do
    it 'returns the normalized target state for valid transitions' do
      expect(described_class.validate_transition!(from: :running, to: 'cancelled')).to eq(:cancelled)
      expect(described_class.validate_transition!(from: :running, to: :queued)).to eq(:queued)
      expect(described_class.validate_transition!(from: :failed, to: 'retry-pending')).to eq(:retry_pending)
    end

    it 'rejects invalid transitions' do
      expect { described_class.validate_transition!(from: :cancelled, to: :running) }
        .to raise_error(Karya::JobLifecycle::InvalidJobTransitionError, /Cannot transition/)
    end
  end
end
