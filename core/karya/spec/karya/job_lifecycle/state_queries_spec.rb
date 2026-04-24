# frozen_string_literal: true

RSpec.describe 'Karya::JobLifecycle::StateQueries' do
  subject(:state_manager) { Karya::JobLifecycle::StateManager.new }

  it 'returns symbol values for canonical public states' do
    expect(state_manager.send(:public_state, 'queued')).to eq(:queued)
  end

  it 'returns frozen public transition values' do
    expect(state_manager.send(:transition_values, %w[queued paused])).to eq([:queued, 'paused'])
  end
end
