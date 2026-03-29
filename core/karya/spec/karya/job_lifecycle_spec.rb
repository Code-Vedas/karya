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
      expect { described_class.normalize_state('___') }
        .to raise_error(Karya::InvalidJobStateError, /state must be present/)
    end

    it 'normalizes punctuation and spacing to snake_case names' do
      described_class.register_state('dead letter!')

      expect(described_class.normalize_state(' dead letter! ')).to eq('dead_letter')
    end
  end

  describe '.validate_state!' do
    it 'returns known states unchanged' do
      expect(described_class.validate_state!(:queued)).to eq(:queued)
      expect(described_class.validate_state!(' Queued ')).to eq(:queued)
      expect(described_class.validate_state!('retry-pending')).to eq(:retry_pending)
    end

    it 'rejects unknown states' do
      expect { described_class.validate_state!(:unknown) }
        .to raise_error(Karya::InvalidJobStateError, /Unknown job state: "unknown"/)
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

      described_class.register_state(:dead_letter, terminal: true)
      described_class.register_transition(from: :retry_pending, to: :dead_letter)

      expect(described_class.transitions).not_to eq(initial_transitions)
    end

    it 'includes empty transition arrays for extension states without outgoing transitions' do
      described_class.register_state(:dead_letter)

      transition_map = described_class.transitions

      expect(transition_map).to include('dead_letter' => [])
      expect(transition_map['dead_letter']).to be_frozen
    end
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

  describe 'private helpers' do
    it 'does not expose cache invalidation as a public module API' do
      expect(described_class.respond_to?(:invalidate_caches!)).to be(false)
      expect(described_class.respond_to?(:invalidate_caches!, true)).to be(true)
    end

    it 'does not expose extension reset as a public module API' do
      expect(described_class.respond_to?(:clear_extensions!)).to be(false)
      expect(described_class.respond_to?(:clear_extensions!, true)).to be(true)
    end

    it 'does not expose raw state normalization as a public module API' do
      expect(described_class.respond_to?(:normalize_state_name)).to be(false)
      expect(described_class.respond_to?(:normalize_state_name, true)).to be(true)
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
        .to raise_error(Karya::InvalidJobTransitionError, /Cannot transition/)
    end
  end

  describe 'extensions' do
    it 'allows later lifecycle states to be registered and linked to canonical states' do
      expect(described_class.register_state(:dead_letter, terminal: true)).to eq('dead_letter')
      described_class.register_transition(from: :retry_pending, to: 'dead_letter')

      expect(described_class.normalize_state('dead-letter')).to eq('dead_letter')
      expect(described_class.valid_transition?(from: :retry_pending, to: 'dead_letter')).to be(true)
      expect(described_class.terminal?('dead_letter')).to be(true)
    end

    it 'does not allow extension transitions that redefine canonical states only' do
      described_class.register_state(:dead_letter)

      expect do
        described_class.register_transition(from: :queued, to: :succeeded)
      end.to raise_error(Karya::InvalidJobTransitionError, /must involve at least one registered extension state/)
    end

    it 'does not allow outgoing transitions from terminal extension states' do
      described_class.register_state(:dead_letter, terminal: true)

      expect do
        described_class.register_transition(from: 'dead_letter', to: :queued)
      end.to raise_error(Karya::InvalidJobTransitionError, /terminal states cannot define outgoing transitions/)
    end

    it 'rejects duplicate extension state registration' do
      described_class.register_state(:dead_letter)

      expect { described_class.register_state(:dead_letter) }
        .to raise_error(Karya::InvalidJobStateError, /dead_letter.*already registered/)
    end

    it 'accepts extension state names up to the maximum length' do
      long_name = 'a' * 64

      expect(described_class.register_state(long_name)).to eq(long_name)
    end

    it 'rejects extension state names longer than the maximum length' do
      long_name = 'a' * 65

      expect { described_class.register_state(long_name) }
        .to raise_error(Karya::InvalidJobStateError, /exceeds 64 characters/)
    end

    it 'stores extension state names internally without symbolizing them' do
      described_class.register_state(:dead_letter)

      extension_state_names = described_class.instance_variable_get(:@extension_state_names)
      expect(extension_state_names).to eq(['dead_letter'])
      expect(extension_state_names.first).to be_a(String)
    end

    it 'does not materialize extension states as symbols in public lifecycle views' do
      described_class.register_state(:dead_letter, terminal: true)
      described_class.register_transition(from: :retry_pending, to: 'dead_letter')

      expect(described_class.states).to include('dead_letter')
      expect(described_class.transitions[:retry_pending]).to include('dead_letter')
      expect(described_class.terminal_states).to include('dead_letter')
    end

    it 'does not allow transition registration to a state cleared from the extension registry' do
      described_class.register_state(:dead_letter)
      described_class.send(:clear_extensions!)

      expect { described_class.register_transition(from: :retry_pending, to: 'dead_letter') }
        .to raise_error(Karya::InvalidJobStateError, /Unknown job state: "dead_letter"/)
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
