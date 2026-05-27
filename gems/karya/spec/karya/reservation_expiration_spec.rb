# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Reservation do
  let(:reserved_at) { Time.utc(2026, 3, 27, 12, 0, 0) }
  let(:expires_at) { Time.utc(2026, 3, 27, 12, 0, 30) }

  describe '#expired?' do
    it 'returns true when the lease is at or past its expiration time' do
      reservation = described_class.new(
        token: 'lease_123',
        job_id: 'job_123',
        queue: 'billing',
        worker_id: 'worker-1',
        reserved_at:,
        expires_at:
      )

      expect(reservation.expired?(Time.utc(2026, 3, 27, 12, 0, 29))).to be(false)
      expect(reservation.expired?(expires_at)).to be(true)
    end
  end
end
