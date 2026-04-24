# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::HandlerMatcher' do
  let(:described_class) do
    Karya::QueueStore::InMemory.const_get(:Internal, false).const_get(:HandlerMatcher, false)
  end

  it 'matches all handlers when no names are provided' do
    matcher = described_class.new(nil)

    expect(matcher.include?('billing_sync')).to be(true)
    expect(matcher.subscription_key_part).to be_nil
  end

  it 'normalizes and sorts explicit handler names for subscription keys' do
    matcher = described_class.new([' email_sync ', 'billing_sync'])

    expect(matcher.include?('email_sync')).to be(true)
    expect(matcher.include?('missing')).to be(false)
    expect(matcher.subscription_key_part).to eq(%w[billing_sync email_sync])
  end

  it 'rejects empty handler lists' do
    expect do
      described_class.new([])
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /handler_names must be present/)
  end
end
