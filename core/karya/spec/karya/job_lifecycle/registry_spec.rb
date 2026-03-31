# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::JobLifecycle::Registry do
  subject(:registry) { described_class.new }

  describe 'explicit lifecycle ownership' do
    it 'keeps extension state isolated per registry' do
      other_registry = described_class.new

      registry.register_state('archived', terminal: true)
      registry.register_transition(from: :queued, to: 'archived')

      expect(registry.states).to include('archived')
      expect(registry.validate_transition(from: :queued, to: 'archived')).to eq('archived')
      expect(other_registry.states).not_to include('archived')
      expect(other_registry.validate_transition(from: :queued, to: 'archived')).to be_nil
    end

    it 'offers safe validation helpers alongside bang methods' do
      expect(registry.validate_state(:queued)).to eq(:queued)
      expect(registry.validate_state(:unknown)).to be_nil
      expect(registry.validate_transition(from: :queued, to: :reserved)).to eq(:reserved)
      expect(registry.validate_transition(from: :queued, to: :running)).to be_nil
      expect { registry.validate_state!(:unknown) }.to raise_error(Karya::JobLifecycle::InvalidJobStateError)
      expect { registry.validate_transition!(from: :queued, to: :running) }
        .to raise_error(Karya::JobLifecycle::InvalidJobTransitionError)
    end

    it 'clears extension state through both clear helpers' do
      registry.register_state('archived', terminal: true)
      registry.register_transition(from: :queued, to: 'archived')

      expect(registry.states).to include('archived')

      registry.clear_extensions

      expect(registry.states).not_to include('archived')
      expect(registry.terminal_states).not_to include('archived')
      expect(registry.validate_transition(from: :queued, to: 'archived')).to be_nil
    end
  end
end
