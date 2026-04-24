# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::InMemory, :integration do
  subject(:store) { described_class.new(token_generator: -> { 'lease-token' }) }

  let(:base_time) { Time.utc(2026, 4, 7, 12, 0, 0) }

  def submission_job(id:)
    Karya::Job.new(
      id:,
      queue: 'billing',
      handler: 'billing_sync',
      arguments: { 'account_id' => 42 },
      state: :submission,
      created_at: base_time
    )
  end

  it 'requeues an expired reservation and allows another worker to reserve the same job' do
    store.enqueue(job: submission_job(id: 'job-reservation'), now: base_time)
    reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 5, now: base_time + 1)

    expect do
      store.start_execution(reservation_token: reservation.token, now: base_time + 10)
    end.to raise_error(Karya::ExpiredReservationError)

    replacement = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 5, now: base_time + 11)

    expect(replacement.job_id).to eq('job-reservation')
    expect { store.release(reservation_token: replacement.token, now: base_time + 12) }.not_to raise_error
  end

  it 'requeues an expired execution so the job can be retried deterministically' do
    store.enqueue(job: submission_job(id: 'job-execution'), now: base_time)
    reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 1, now: base_time + 1)
    store.start_execution(reservation_token: reservation.token, now: base_time + 1.5)

    expect do
      store.complete_execution(reservation_token: reservation.token, now: base_time + 5)
    end.to raise_error(Karya::ExpiredReservationError)

    replacement = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 5, now: base_time + 6)

    expect(replacement.job_id).to eq('job-execution')
    retried_job = store.start_execution(reservation_token: replacement.token, now: base_time + 6.5)
    expect(retried_job.attempt).to eq(2)
  end

  it 'keeps recovered until-terminal uniqueness blocked until the recovered job completes' do
    store.enqueue(
      job: Karya::Job.new(
        id: 'job-1',
        queue: 'billing',
        handler: 'billing_sync',
        arguments: { 'account_id' => 42 },
        uniqueness_key: 'billing:account-42',
        uniqueness_scope: :until_terminal,
        state: :submission,
        created_at: base_time
      ),
      now: base_time
    )
    reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 1, now: base_time + 1)
    store.start_execution(reservation_token: reservation.token, now: base_time + 1.5)

    report = store.recover_in_flight(now: base_time + 5)
    recovered_job = report.recovered_running_jobs.find { |job| job.id == 'job-1' }

    expect(recovered_job&.state).to eq(:queued)
    expect do
      store.enqueue(
        job: Karya::Job.new(
          id: 'job-2',
          queue: 'billing',
          handler: 'billing_sync',
          arguments: { 'account_id' => 42 },
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :until_terminal,
          state: :submission,
          created_at: base_time + 5
        ),
        now: base_time + 5
      )
    end.to raise_error(Karya::DuplicateUniquenessKeyError, /billing:account-42/)

    replacement = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 5, now: base_time + 6)
    expect(replacement.job_id).to eq('job-1')
    store.start_execution(reservation_token: replacement.token, now: base_time + 6.5)
    store.complete_execution(reservation_token: replacement.token, now: base_time + 7)

    expect do
      store.enqueue(
        job: Karya::Job.new(
          id: 'job-2',
          queue: 'billing',
          handler: 'billing_sync',
          arguments: { 'account_id' => 42 },
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :until_terminal,
          state: :submission,
          created_at: base_time + 7
        ),
        now: base_time + 7
      )
    end.not_to raise_error
  end
end
