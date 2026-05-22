# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::Reservation::Attributes' do
  let(:attributes_class) { Karya::Reservation.const_get(:Attributes, false) }
  let(:reserved_at) { Time.utc(2026, 3, 26, 12, 0, 0) }
  let(:expires_at) { Time.utc(2026, 3, 26, 12, 5, 0) }

  describe '#to_h' do
    it 'normalizes all reservation attributes into canonical hash' do
      attributes = attributes_class.new(
        token: 'tok123',
        job_id: 'job456',
        queue: 'billing',
        worker_id: 'worker789',
        reserved_at: reserved_at,
        expires_at: expires_at
      )

      result = attributes.to_h

      expect(result[:token]).to eq('tok123')
      expect(result[:job_id]).to eq('job456')
      expect(result[:queue]).to eq('billing')
      expect(result[:worker_id]).to eq('worker789')
      expect(result[:reserved_at]).to eq(reserved_at)
      expect(result[:expires_at]).to eq(expires_at)
    end

    it 'raises InvalidReservationAttributeError when required field is missing' do
      expect do
        attributes_class.new(
          job_id: 'job456',
          queue: 'billing',
          worker_id: 'worker789',
          reserved_at: reserved_at,
          expires_at: expires_at
        ).to_h
      end.to raise_error(Karya::InvalidReservationAttributeError, 'token must be present')
    end

    it 'raises InvalidReservationAttributeError when expires_at is not after reserved_at' do
      expect do
        attributes_class.new(
          token: 'tok123',
          job_id: 'job456',
          queue: 'billing',
          worker_id: 'worker789',
          reserved_at: expires_at,
          expires_at: reserved_at
        ).to_h
      end.to raise_error(Karya::InvalidReservationAttributeError, 'expires_at must be after reserved_at')
    end

    it 'raises InvalidReservationAttributeError when expires_at equals reserved_at' do
      expect do
        attributes_class.new(
          token: 'tok123',
          job_id: 'job456',
          queue: 'billing',
          worker_id: 'worker789',
          reserved_at: reserved_at,
          expires_at: reserved_at
        ).to_h
      end.to raise_error(Karya::InvalidReservationAttributeError, 'expires_at must be after reserved_at')
    end

    it 'normalizes identifier fields using IdentifierNormalizer' do
      attributes = attributes_class.new(
        token: '  tok123  ',
        job_id: :job456,
        queue: 'billing',
        worker_id: 'worker789',
        reserved_at: reserved_at,
        expires_at: expires_at
      )

      result = attributes.to_h

      expect(result[:token]).to eq('tok123')
      expect(result[:job_id]).to eq('job456')
    end

    it 'normalizes timestamp fields using TimestampNormalizer' do
      mutable_reserved_at = reserved_at.dup
      mutable_expires_at = expires_at.dup

      attributes = attributes_class.new(
        token: 'tok123',
        job_id: 'job456',
        queue: 'billing',
        worker_id: 'worker789',
        reserved_at: mutable_reserved_at,
        expires_at: mutable_expires_at
      )

      result = attributes.to_h

      expect(result[:reserved_at]).to be_frozen
      expect(result[:expires_at]).to be_frozen
      expect(result[:reserved_at].object_id).not_to eq(mutable_reserved_at.object_id)
      expect(result[:expires_at].object_id).not_to eq(mutable_expires_at.object_id)
    end
  end
end
