# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

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
