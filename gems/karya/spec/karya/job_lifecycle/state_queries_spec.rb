# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::JobLifecycle::StateQueries' do
  subject(:state_manager) { Karya::JobLifecycle::StateManager.new }

  it 'returns symbol values for canonical public states' do
    expect(state_manager.send(:public_state, 'queued')).to eq(:queued)
  end

  it 'returns frozen public transition values' do
    expect(state_manager.send(:transition_values, %w[queued paused])).to eq([:queued, 'paused'])
  end
end
