# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'bigdecimal'

RSpec.describe Karya::Internal::DurableQueueStore::LeaseDuration do
  it 'accepts positive integer, rational, float, and decimal lease durations' do
    expect(described_class.new(30).normalize).to eq(30)
    expect(described_class.new(Rational(3, 2)).normalize).to eq(Rational(3, 2))
    expect(described_class.new(0.5).normalize).to eq(0.5)
    expect(described_class.new(BigDecimal('1.25')).normalize).to eq(BigDecimal('1.25'))
  end

  it 'rejects non-positive and non-finite durations' do
    [0, -1, 0.0, Float::INFINITY, -Float::INFINITY].each do |value|
      expect do
        described_class.new(value).normalize
      end.to raise_error(Karya::InvalidQueueStoreOperationError, 'lease_duration must be a positive number')
    end
  end

  it 'rejects unsupported lease duration types' do
    expect do
      described_class.new('30').normalize
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'lease_duration must be a positive number')
  end
end
