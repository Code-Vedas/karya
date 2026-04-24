# frozen_string_literal: true

RSpec.describe Karya::JobLifecycle::InvalidJobStateError do
  it 'defines lifecycle-specific error classes under Karya::Error' do
    expect(described_class).to be < Karya::Error
    expect(Karya::JobLifecycle::InvalidJobTransitionError).to be < Karya::Error
  end
end
