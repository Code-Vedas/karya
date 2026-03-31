# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Reservation::TimestampNormalizer do
  describe '#normalize' do
    it 'duplicates and freezes Time object' do
      time = Time.utc(2026, 3, 26, 12, 0, 0)
      normalizer = described_class.new(:reserved_at, time)
      result = normalizer.normalize

      expect(result).to eq(time)
      expect(result).to be_frozen
      expect(result.object_id).not_to eq(time.object_id)
    end

    it 'returns frozen copy even if original is frozen' do
      time = Time.utc(2026, 3, 26, 12, 0, 0).freeze
      normalizer = described_class.new(:expires_at, time)
      result = normalizer.normalize

      expect(result).to eq(time)
      expect(result).to be_frozen
      expect(result.object_id).not_to eq(time.object_id)
    end

    it 'raises InvalidReservationAttributeError for non-Time value' do
      expect do
        described_class.new(:reserved_at, '2026-03-26').normalize
      end.to raise_error(Karya::InvalidReservationAttributeError, 'reserved_at must be a Time')
    end

    it 'raises InvalidReservationAttributeError for integer timestamp' do
      expect do
        described_class.new(:expires_at, 1_234_567_890).normalize
      end.to raise_error(Karya::InvalidReservationAttributeError, 'expires_at must be a Time')
    end

    it 'raises InvalidReservationAttributeError for nil value' do
      expect do
        described_class.new(:reserved_at, nil).normalize
      end.to raise_error(Karya::InvalidReservationAttributeError, 'reserved_at must be a Time')
    end

    it 'raises InvalidReservationAttributeError for DateTime object' do
      require 'date'
      datetime = DateTime.now

      expect do
        described_class.new(:expires_at, datetime).normalize
      end.to raise_error(Karya::InvalidReservationAttributeError, 'expires_at must be a Time')
    end
  end
end
