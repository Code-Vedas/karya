# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Reservation do
  let(:reserved_at) { Time.utc(2026, 3, 27, 12, 0, 0) }
  let(:expires_at) { Time.utc(2026, 3, 27, 12, 0, 30) }

  describe '#initialize' do
    it 'builds an immutable reservation with normalized fields' do
      reservation = described_class.new(
        token: 'lease-123',
        job_id: 'job-123',
        queue: ' billing ',
        worker_id: ' worker-1 ',
        reserved_at:,
        expires_at:
      )

      expect(reservation.token).to eq('lease-123')
      expect(reservation.job_id).to eq('job-123')
      expect(reservation.queue).to eq('billing')
      expect(reservation.worker_id).to eq('worker-1')
      expect(reservation.token).to be_frozen
      expect(reservation.job_id).to be_frozen
      expect(reservation.queue).to be_frozen
      expect(reservation.worker_id).to be_frozen
      expect(reservation.reserved_at).to eq(reserved_at)
      expect(reservation.expires_at).to eq(expires_at)
      expect(reservation.reserved_at).to be_frozen
      expect(reservation.expires_at).to be_frozen
      expect(reservation).to be_frozen
    end

    it 'rejects missing required fields' do
      expect do
        described_class.new(
          token: 'lease_123',
          queue: 'billing',
          worker_id: 'worker-1',
          reserved_at:,
          expires_at:
        )
      end.to raise_error(Karya::InvalidReservationAttributeError, /job_id must be present/)
    end

    it 'rejects blank identifiers' do
      expect do
        described_class.new(
          token: ' ',
          job_id: 'job_123',
          queue: 'billing',
          worker_id: 'worker-1',
          reserved_at:,
          expires_at:
        )
      end.to raise_error(Karya::InvalidReservationAttributeError, /token must be present/)
    end

    it 'rejects non-time timestamps' do
      expect do
        described_class.new(
          token: 'lease_123',
          job_id: 'job_123',
          queue: 'billing',
          worker_id: 'worker-1',
          reserved_at: '2026-03-27T12:00:00Z',
          expires_at:
        )
      end.to raise_error(Karya::InvalidReservationAttributeError, /reserved_at must be a Time/)
    end

    it 'rejects expirations at or before the reservation time' do
      expect do
        described_class.new(
          token: 'lease_123',
          job_id: 'job_123',
          queue: 'billing',
          worker_id: 'worker-1',
          reserved_at:,
          expires_at: reserved_at
        )
      end.to raise_error(Karya::InvalidReservationAttributeError, /expires_at must be after reserved_at/)
    end
  end
end
