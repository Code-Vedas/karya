# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::JobLifecycle::Extension do
  let(:state_manager) { Karya::JobLifecycle::StateManager.new }

  describe '.register_state' do
    it 'registers a new extension state' do
      result = described_class.register_state('pending_approval', state_manager: state_manager)

      expect(result).to eq('pending_approval')
      expect(state_manager.states).to include('pending_approval')
    end

    it 'normalizes the state name before registration' do
      result = described_class.register_state('Pending Approval', state_manager: state_manager)

      expect(result).to eq('pending_approval')
      expect(state_manager.states).to include('pending_approval')
    end

    it 'registers a terminal extension state' do
      described_class.register_state('archived', state_manager: state_manager, terminal: true)

      expect(state_manager.terminal_states).to include('archived')
    end

    it 'does not mark state as terminal by default' do
      described_class.register_state('pending_approval', state_manager: state_manager)

      expect(state_manager.terminal_states).not_to include('pending_approval')
    end

    it 'raises Karya::JobLifecycle::InvalidJobStateError when registering duplicate state' do
      described_class.register_state('pending_approval', state_manager: state_manager)

      expect do
        described_class.register_state('pending_approval', state_manager: state_manager)
      end.to raise_error(Karya::JobLifecycle::InvalidJobStateError, /already registered/)
    end

    it 'raises Karya::JobLifecycle::InvalidJobStateError when registering canonical state' do
      expect do
        described_class.register_state('queued', state_manager: state_manager)
      end.to raise_error(Karya::JobLifecycle::InvalidJobStateError, /already registered/)
    end

    it 'freezes the returned state name' do
      result = described_class.register_state('pending_approval', state_manager: state_manager)

      expect(result).to be_frozen
    end

    it 'invalidates state manager caches' do
      described_class.register_state('pending_approval', state_manager: state_manager)

      states_before = state_manager.states
      described_class.register_state('pending_review', state_manager: state_manager)
      states_after = state_manager.states

      expect(states_after.size).to eq(states_before.size + 1)
    end
  end

  describe '.register_transition' do
    before do
      described_class.register_state('pending_approval', state_manager: state_manager)
    end

    it 'registers a transition from canonical state to extension state' do
      result = described_class.register_transition(
        from: :queued,
        to: 'pending_approval',
        state_manager: state_manager
      )

      expect(result).to eq('pending_approval')
      expect(state_manager.valid_transition?(from: :queued, to: 'pending_approval')).to be true
    end

    it 'registers a transition from extension state to canonical state' do
      described_class.register_transition(
        from: 'pending_approval',
        to: :queued,
        state_manager: state_manager
      )

      expect(state_manager.valid_transition?(from: 'pending_approval', to: :queued)).to be true
    end

    it 'registers a transition between extension states' do
      described_class.register_state('pending_review', state_manager: state_manager)

      described_class.register_transition(
        from: 'pending_approval',
        to: 'pending_review',
        state_manager: state_manager
      )

      expect(state_manager.valid_transition?(from: 'pending_approval', to: 'pending_review')).to be true
    end

    it 'raises Karya::JobLifecycle::InvalidJobTransitionError when neither state is an extension' do
      expect do
        described_class.register_transition(
          from: :queued,
          to: :running,
          state_manager: state_manager
        )
      end.to raise_error(Karya::JobLifecycle::InvalidJobTransitionError, /must involve at least one registered extension state/)
    end

    it 'raises Karya::JobLifecycle::InvalidJobTransitionError when from state is terminal' do
      described_class.register_state('archived', state_manager: state_manager, terminal: true)

      expect do
        described_class.register_transition(
          from: 'archived',
          to: :queued,
          state_manager: state_manager
        )
      end.to raise_error(Karya::JobLifecycle::InvalidJobTransitionError, /terminal states cannot define outgoing transitions/)
    end

    it 'allows multiple transitions from the same state' do
      described_class.register_state('pending_review', state_manager: state_manager)

      described_class.register_transition(from: 'pending_approval', to: :queued, state_manager: state_manager)
      described_class.register_transition(from: 'pending_approval', to: 'pending_review', state_manager: state_manager)

      expect(state_manager.valid_transition?(from: 'pending_approval', to: :queued)).to be true
      expect(state_manager.valid_transition?(from: 'pending_approval', to: 'pending_review')).to be true
    end

    it 'invalidates state manager caches' do
      state_manager.transitions

      described_class.register_transition(
        from: 'pending_approval',
        to: :queued,
        state_manager: state_manager
      )

      transitions_after = state_manager.transitions
      expect(transitions_after['pending_approval']).not_to be_empty
    end
  end

  describe '.clear_extensions!' do
    before do
      described_class.register_state('pending_approval', state_manager: state_manager)
      described_class.register_state('archived', state_manager: state_manager, terminal: true)
      described_class.register_transition(from: 'pending_approval', to: :queued, state_manager: state_manager)
    end

    it 'removes all registered extension states' do
      described_class.clear_extensions!(state_manager: state_manager)

      expect(state_manager.states).not_to include('pending_approval')
      expect(state_manager.states).not_to include('archived')
    end

    it 'removes all registered extension terminal states' do
      described_class.clear_extensions!(state_manager: state_manager)

      expect(state_manager.terminal_states).not_to include('archived')
    end

    it 'removes all registered extension transitions' do
      described_class.clear_extensions!(state_manager: state_manager)

      # After clearing extensions, the transition and state should no longer exist
      expect(state_manager.states).not_to include('pending_approval')
      expect do
        state_manager.validate_transition!(from: 'pending_approval', to: :queued)
      end.to raise_error(Karya::JobLifecycle::InvalidJobStateError)
    end

    it 'preserves canonical states and transitions' do
      described_class.clear_extensions!(state_manager: state_manager)

      expect(state_manager.states).to include(:queued)
      expect(state_manager.valid_transition?(from: :queued, to: :reserved)).to be true
    end

    it 'invalidates state manager caches' do
      described_class.clear_extensions!(state_manager: state_manager)

      states = state_manager.states
      expect(states).not_to include('pending_approval')
    end
  end
end
