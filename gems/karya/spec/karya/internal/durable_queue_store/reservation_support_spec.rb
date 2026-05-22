# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::ReservationSupport do
  let(:host_class) do
    Class.new do
      include Karya::Internal::DurableQueueStore::SharedSupport
      include Karya::Internal::DurableQueueStore::ReservationSupport

      attr_accessor :reservation_token_sequence
      attr_writer :reservation_token_in_use

      def token_generator
        -> { " token \n" }
      end

      def reservation_token_in_use?(reservation_token)
        @reservation_token_in_use && reservation_token == 'token:1'
      end

      public :next_token, :build_reservation, :ensure_unique_reservation_token
    end
  end
  let(:host) do
    host_class.new.tap do |instance|
      instance.reservation_token_sequence = 0
      instance.reservation_token_in_use = false
    end
  end
  let(:job) { Karya::Job.new(id: 'job-1', queue: 'billing', handler: 'sync', state: :queued, created_at: Time.utc(2026, 5, 23, 12, 0, 0)) }
  let(:reserved_at) { Time.utc(2026, 5, 23, 12, 1, 0) }

  it 'builds sequential reservations from normalized tokens' do
    reservation = host.build_reservation(
      reserved_job: job,
      worker_id: 'worker-1',
      reserved_at:,
      lease_duration: 30
    )

    expect(reservation.token).to eq('token:1')
    expect(reservation.job_id).to eq('job-1')
    expect(reservation.queue).to eq('billing')
    expect(reservation.worker_id).to eq('worker-1')
    expect(reservation.expires_at).to eq(reserved_at + 30)
  end

  it 'rejects duplicate reservation tokens' do
    host.reservation_token_in_use = true

    expect do
      host.build_reservation(
        reserved_job: job,
        worker_id: 'worker-1',
        reserved_at:,
        lease_duration: 30
      )
    end.to raise_error(Karya::DuplicateReservationTokenError, /reservation token "token:1" is already in use/)
  end
end
