# frozen_string_literal: true

RSpec.describe Karya::Backend::Descriptor do
  it 'normalizes the backend identifier' do
    descriptor = described_class.new(identifier: ' InMemory ')

    expect(descriptor.identifier).to eq('in_memory')
    expect(descriptor).to be_frozen
  end
end
