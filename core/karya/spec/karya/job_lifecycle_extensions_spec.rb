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

  describe 'extensions' do
    it 'allows later lifecycle states to be registered and linked to canonical states' do
      expect(described_class.register_state(:quarantine, terminal: true)).to eq('quarantine')
      described_class.register_transition(from: :retry_pending, to: 'quarantine')

      expect(described_class.normalize_state('quarantine')).to eq('quarantine')
      expect(described_class.valid_transition?(from: :retry_pending, to: 'quarantine')).to be(true)
      expect(described_class.terminal?('quarantine')).to be(true)
    end

    it 'does not allow extension transitions that redefine canonical states only' do
      described_class.register_state(:quarantine)

      expect do
        described_class.register_transition(from: :queued, to: :succeeded)
      end.to raise_error(Karya::JobLifecycle::InvalidJobTransitionError, /must involve at least one registered extension state/)
    end

    it 'does not allow outgoing transitions from terminal extension states' do
      described_class.register_state(:quarantine, terminal: true)

      expect do
        described_class.register_transition(from: 'quarantine', to: :queued)
      end.to raise_error(Karya::JobLifecycle::InvalidJobTransitionError, /terminal states cannot define outgoing transitions/)
    end

    it 'rejects duplicate extension state registration' do
      described_class.register_state(:quarantine)

      expect { described_class.register_state(:quarantine) }
        .to raise_error(Karya::JobLifecycle::InvalidJobStateError, /quarantine.*already registered/)
    end

    it 'accepts extension state names up to the maximum length' do
      long_name = 'a' * 64

      expect(described_class.register_state(long_name)).to eq(long_name)
    end

    it 'rejects extension state names longer than the maximum length' do
      long_name = 'a' * 65

      expect { described_class.register_state(long_name) }
        .to raise_error(Karya::JobLifecycle::InvalidJobStateError, /exceeds 64 characters/)
    end

    it 'stores extension state names internally without symbolizing them' do
      described_class.register_state(:quarantine)

      extension_state_names = described_class.default_registry.send(:extension_state_names)
      expect(extension_state_names).to eq(['quarantine'])
      expect(extension_state_names.first).to be_a(String)
    end

    it 'does not materialize extension states as symbols in public lifecycle views' do
      described_class.register_state(:quarantine, terminal: true)
      described_class.register_transition(from: :retry_pending, to: 'quarantine')

      expect(described_class.states).to include('quarantine')
      expect(described_class.transitions[:retry_pending]).to include('quarantine')
      expect(described_class.terminal_states).to include('quarantine')
    end

    it 'does not allow transition registration to a state cleared from the extension registry' do
      described_class.register_state(:quarantine)
      described_class.send(:clear_extensions!)

      expect { described_class.register_transition(from: :retry_pending, to: 'quarantine') }
        .to raise_error(Karya::JobLifecycle::InvalidJobStateError, /Unknown job state: "quarantine"/)
    end
  end
end
