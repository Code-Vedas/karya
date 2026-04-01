# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::JobLifecycle::StateManager do
  let(:state_manager) { described_class.new }

  describe '#initialize' do
    it 'initializes with empty extension arrays' do
      expect(state_manager.extension_state_names).to eq([])
      expect(state_manager.extension_terminal_state_names).to eq([])
      expect(state_manager.extension_transitions).to be_a(Hash)
    end

    it 'initializes with a mutex' do
      expect(state_manager.send(:mutex)).to be_a(Mutex)
    end
  end

  describe '#normalize_state' do
    it 'normalizes and validates canonical state symbol' do
      expect(state_manager.normalize_state(:queued)).to eq(:queued)
    end

    it 'normalizes and validates canonical state string' do
      expect(state_manager.normalize_state('retry-pending')).to eq(:retry_pending)
    end

    it 'raises Karya::JobLifecycle::InvalidJobStateError for unknown state' do
      expect do
        state_manager.normalize_state('unknown_state')
      end.to raise_error(Karya::JobLifecycle::InvalidJobStateError, /Unknown job state/)
    end
  end

  describe '#validate_state!' do
    it 'validates and returns canonical state as symbol' do
      expect(state_manager.validate_state!(:queued)).to eq(:queued)
    end

    it 'validates and returns extension state as string' do
      Karya::JobLifecycle::Extension.register_state('custom_state', state_manager: state_manager)

      expect(state_manager.validate_state!('custom_state')).to eq('custom_state')
    end

    it 'raises Karya::JobLifecycle::InvalidJobStateError for unknown state' do
      expect do
        state_manager.validate_state!('unknown')
      end.to raise_error(Karya::JobLifecycle::InvalidJobStateError)
    end
  end

  describe '#valid_transition?' do
    it 'returns true for valid canonical transition' do
      expect(state_manager.valid_transition?(from: :queued, to: :reserved)).to be true
    end

    it 'returns false for invalid canonical transition' do
      expect(state_manager.valid_transition?(from: :queued, to: :running)).to be false
    end

    it 'returns false for transition from terminal state' do
      expect(state_manager.valid_transition?(from: :succeeded, to: :queued)).to be false
    end

    it 'handles extension state transitions' do
      Karya::JobLifecycle::Extension.register_state('custom', state_manager: state_manager)
      Karya::JobLifecycle::Extension.register_transition(from: :queued, to: 'custom', state_manager: state_manager)

      expect(state_manager.valid_transition?(from: :queued, to: 'custom')).to be true
    end
  end

  describe '#validate_transition!' do
    it 'validates and returns target state for valid transition' do
      expect(state_manager.validate_transition!(from: :queued, to: :reserved)).to eq(:reserved)
    end

    it 'raises Karya::JobLifecycle::InvalidJobTransitionError for invalid transition' do
      expect do
        state_manager.validate_transition!(from: :queued, to: :running)
      end.to raise_error(Karya::JobLifecycle::InvalidJobTransitionError, /Cannot transition/)
    end

    it 'includes state names in error message' do
      expect do
        state_manager.validate_transition!(from: :succeeded, to: :queued)
      end.to raise_error(Karya::JobLifecycle::InvalidJobTransitionError, /succeeded.*queued/)
    end
  end

  describe '#terminal?' do
    it 'returns true for terminal states' do
      expect(state_manager.terminal?(:succeeded)).to be true
      expect(state_manager.terminal?(:cancelled)).to be true
    end

    it 'returns false for non-terminal states' do
      expect(state_manager.terminal?(:queued)).to be false
      expect(state_manager.terminal?(:running)).to be false
    end

    it 'handles extension terminal states' do
      Karya::JobLifecycle::Extension.register_state('archived', state_manager: state_manager, terminal: true)

      expect(state_manager.terminal?('archived')).to be true
    end
  end

  describe '#states' do
    it 'returns all canonical states as symbols' do
      states = state_manager.states

      expect(states).to include(:queued, :reserved, :running, :succeeded, :failed, :cancelled)
    end

    it 'includes extension states as strings' do
      Karya::JobLifecycle::Extension.register_state('custom', state_manager: state_manager)

      states = state_manager.states

      expect(states).to include('custom')
      expect(states).to include(:queued)
    end

    it 'returns frozen array' do
      expect(state_manager.states).to be_frozen
    end
  end

  describe '#transitions' do
    it 'returns canonical transitions' do
      transitions = state_manager.transitions

      expect(transitions[:queued]).to include(:reserved, :cancelled)
      expect(transitions[:succeeded]).to eq([])
    end

    it 'includes extension transitions' do
      Karya::JobLifecycle::Extension.register_state('custom', state_manager: state_manager)
      Karya::JobLifecycle::Extension.register_transition(from: :queued, to: 'custom', state_manager: state_manager)

      transitions = state_manager.transitions

      expect(transitions[:queued]).to include('custom')
    end

    it 'returns frozen structure' do
      transitions = state_manager.transitions

      expect(transitions).to be_frozen
      transitions.each_value do |values|
        expect(values).to be_frozen
      end
    end
  end

  describe '#terminal_states' do
    it 'returns canonical terminal states' do
      terminal_states = state_manager.terminal_states

      expect(terminal_states).to contain_exactly(:succeeded, :cancelled)
    end

    it 'includes extension terminal states' do
      Karya::JobLifecycle::Extension.register_state('archived', state_manager: state_manager, terminal: true)

      terminal_states = state_manager.terminal_states

      expect(terminal_states).to include('archived')
      expect(terminal_states).to include(:succeeded, :cancelled)
    end

    it 'returns frozen array' do
      expect(state_manager.terminal_states).to be_frozen
    end
  end

  describe '#normalize_state_locked' do
    it 'normalizes and validates state (locked version)' do
      expect(state_manager.send(:normalize_state_locked, :queued)).to eq('queued')
    end

    it 'raises Karya::JobLifecycle::InvalidJobStateError for unknown state' do
      expect do
        state_manager.send(:normalize_state_locked, 'unknown')
      end.to raise_error(Karya::JobLifecycle::InvalidJobStateError)
    end
  end

  describe '#state_names_locked' do
    it 'returns canonical state names' do
      state_names = state_manager.send(:state_names_locked)

      expect(state_names).to include('queued', 'reserved', 'running')
    end

    it 'includes extension state names' do
      Karya::JobLifecycle::Extension.register_state('custom', state_manager: state_manager)

      state_names = state_manager.send(:state_names_locked)

      expect(state_names).to include('custom')
    end

    it 'is frozen' do
      expect(state_manager.send(:state_names_locked)).to be_frozen
    end

    it 'caches the result' do
      first_call = state_manager.send(:state_names_locked)
      second_call = state_manager.send(:state_names_locked)

      expect(first_call.object_id).to eq(second_call.object_id)
    end
  end

  describe '#transition_names_locked' do
    it 'returns transition names map' do
      transitions = state_manager.send(:transition_names_locked)

      expect(transitions['queued']).to include('reserved', 'cancelled')
    end

    it 'is frozen' do
      expect(state_manager.send(:transition_names_locked)).to be_frozen
    end

    it 'has frozen value arrays' do
      state_manager.send(:transition_names_locked).each_value do |values|
        expect(values).to be_frozen
      end
    end

    it 'caches the result' do
      first_call = state_manager.send(:transition_names_locked)
      second_call = state_manager.send(:transition_names_locked)

      expect(first_call.object_id).to eq(second_call.object_id)
    end
  end

  describe '#terminal_state_names_locked' do
    it 'returns terminal state names' do
      terminal_names = state_manager.send(:terminal_state_names_locked)

      expect(terminal_names).to include('succeeded', 'cancelled')
    end

    it 'is frozen' do
      expect(state_manager.send(:terminal_state_names_locked)).to be_frozen
    end

    it 'caches the result' do
      first_call = state_manager.send(:terminal_state_names_locked)
      second_call = state_manager.send(:terminal_state_names_locked)

      expect(first_call.object_id).to eq(second_call.object_id)
    end
  end

  describe '#invalidate_caches' do
    it 'clears cached state names' do
      first_states = state_manager.send(:state_names_locked)

      Karya::JobLifecycle::Extension.register_state('custom', state_manager: state_manager)

      second_states = state_manager.send(:state_names_locked)

      expect(second_states).to include('custom')
      expect(first_states).not_to include('custom')
    end

    it 'clears cached transition names' do
      state_manager.send(:transition_names_locked)

      Karya::JobLifecycle::Extension.register_state('custom', state_manager: state_manager)
      Karya::JobLifecycle::Extension.register_transition(from: :queued, to: 'custom', state_manager: state_manager)

      transitions = state_manager.send(:transition_names_locked)

      expect(transitions['queued']).to include('custom')
    end

    it 'clears cached terminal state names' do
      state_manager.send(:terminal_state_names_locked)

      Karya::JobLifecycle::Extension.register_state('archived', state_manager: state_manager, terminal: true)

      terminal_names = state_manager.send(:terminal_state_names_locked)

      expect(terminal_names).to include('archived')
    end
  end

  describe '#validate_state_locked!' do
    it 'validates and returns state name' do
      expect(state_manager.send(:validate_state_locked!, 'queued')).to eq('queued')
    end

    it 'raises Karya::JobLifecycle::InvalidJobStateError for unknown state' do
      expect do
        state_manager.send(:validate_state_locked!, 'unknown')
      end.to raise_error(Karya::JobLifecycle::InvalidJobStateError)
    end
  end

  describe '#validate_state_locked' do
    it 'returns the validated state name for known states' do
      expect(state_manager.send(:validate_state_locked, 'queued')).to eq('queued')
    end

    it 'returns nil for unknown states' do
      expect(state_manager.send(:validate_state_locked, 'unknown')).to be_nil
    end
  end

  describe '#validate_state' do
    it 'returns the public state for valid states' do
      expect(state_manager.validate_state('queued')).to eq(:queued)
    end

    it 'returns nil for invalid states' do
      expect(state_manager.validate_state('unknown')).to be_nil
    end
  end

  describe '#validate_transition' do
    it 'returns the target state for valid transitions' do
      expect(state_manager.validate_transition(from: :queued, to: :reserved)).to eq(:reserved)
    end

    it 'returns nil for invalid transitions' do
      expect(state_manager.validate_transition(from: :queued, to: :running)).to be_nil
    end

    it 'returns nil for unknown states' do
      expect(state_manager.validate_transition(from: :unknown, to: :queued)).to be_nil
    end
  end

  describe '#extension_state_name?' do
    it 'returns false for canonical states' do
      expect(state_manager.send(:extension_state_name?, 'queued')).to be false
    end

    it 'returns true for extension states' do
      Karya::JobLifecycle::Extension.register_state('custom', state_manager: state_manager)

      expect(state_manager.send(:extension_state_name?, 'custom')).to be true
    end
  end

  describe '#public_state' do
    it 'returns symbol for canonical state names' do
      expect(state_manager.send(:public_state, 'queued')).to eq(:queued)
    end

    it 'returns string for extension state names' do
      Karya::JobLifecycle::Extension.register_state('custom', state_manager: state_manager)

      expect(state_manager.send(:public_state, 'custom')).to eq('custom')
    end
  end

  describe 'thread safety' do
    it 'uses mutex for synchronization' do
      allow(state_manager.send(:mutex)).to receive(:synchronize).and_call_original

      state_manager.normalize_state(:queued)

      expect(state_manager.send(:mutex)).to have_received(:synchronize)
    end

    it 'allows concurrent reads after cache invalidation' do
      threads = Array.new(10) do
        Thread.new do
          1000.times do
            state_manager.states
            state_manager.transitions
          end
        end
      end

      threads.each(&:join)

      expect(state_manager.states).not_to be_empty
    end
  end
end
