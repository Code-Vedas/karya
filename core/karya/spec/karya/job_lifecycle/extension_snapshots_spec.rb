# frozen_string_literal: true

RSpec.describe 'Karya::JobLifecycle::ExtensionSnapshots' do
  subject(:state_manager) { Karya::JobLifecycle::StateManager.new }

  it 'returns frozen copies of extension snapshot data' do
    state_manager.send(:synchronize) do
      state_manager.send(:add_extension_state_locked, 'paused', terminal: true)
      state_manager.send(:add_extension_transition_locked, 'queued', 'paused')
    end

    expect(state_manager.extension_state_names).to eq(['paused'])
    expect(state_manager.extension_terminal_state_names).to eq(['paused'])
    expect(state_manager.extension_transitions).to eq({ 'queued' => ['paused'].freeze })
  end
end
