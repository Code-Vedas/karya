# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::HandlerMatcher do
  it 'matches every handler when no handler names are provided' do
    matcher = described_class.new(nil)

    expect(matcher.include?('anything')).to be(true)
    expect(matcher.subscription_key_part).to be_nil
    expect(matcher.handler_names_for_query).to be_nil
  end

  it 'normalizes handler names and exposes a sorted subscription key' do
    matcher = described_class.new([" billing_sync \n", 'email_sync'])

    expect(matcher.include?('billing_sync')).to be(true)
    expect(matcher.include?('email_sync')).to be(true)
    expect(matcher.include?('other')).to be(false)
    expect(matcher.subscription_key_part).to eq(%w[billing_sync email_sync])
    expect(matcher.handler_names_for_query).to match_array(%w[billing_sync email_sync])
  end

  it 'rejects non-array handler_names' do
    expect do
      described_class.new('billing_sync')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'handler_names must be an Array')
  end

  it 'rejects empty and non-string handler entries' do
    expect do
      described_class.new([])
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'handler_names must be present')

    expect do
      described_class.new([:billing_sync])
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'handler_names entries must be Strings')
  end
end
