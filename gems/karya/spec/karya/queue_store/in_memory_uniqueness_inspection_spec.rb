# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::InMemory do
  subject(:store) { described_class.new(token_generator: token_generator) }

  let(:token_sequence) { %w[lease-1 lease-2 lease-3 lease-4 lease-5 lease-6].each }
  let(:token_generator) { -> { token_sequence.next } }
  let(:created_at) { Time.utc(2026, 4, 21, 12, 0, 0) }
  let(:retry_policy) { Karya::RetryPolicy.new(max_attempts: 3, base_delay: 5, multiplier: 1) }

  def submission_job(
    id:,
    created_at:,
    queue: 'billing',
    handler: 'billing_sync',
    idempotency_key: nil,
    uniqueness_key: nil,
    uniqueness_scope: nil,
    expires_at: nil
  )
    Karya::Job.new(
      id:,
      queue:,
      handler:,
      idempotency_key:,
      uniqueness_key:,
      uniqueness_scope:,
      expires_at:,
      state: :submission,
      created_at:
    )
  end

  def expect_deep_frozen(value)
    expect(value).to be_frozen
    case value
    when Hash
      value.each do |key, nested_value|
        expect(key).to be_frozen if key.is_a?(String)
        expect_deep_frozen(nested_value)
      end
    when Array
      value.each { |nested_value| expect_deep_frozen(nested_value) }
    end
  end

  describe '#uniqueness_decision' do
    it 'returns an accepted decision for non-conflicting work' do
      decision = store.uniqueness_decision(
        job: submission_job(id: 'job-1', created_at:),
        now: created_at + 1
      )

      expect(decision).to eq(
        captured_at: created_at + 1,
        job_id: 'job-1',
        action: :accept,
        result: :accepted,
        key_type: nil,
        key: nil,
        conflicting_job_id: nil,
        uniqueness_scope: nil
      )
      expect_deep_frozen(decision)
    end

    it 'reports duplicate job ids before key conflicts' do
      store.enqueue(
        job: submission_job(
          id: 'job-1',
          created_at:,
          idempotency_key: 'submit-123',
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :active
        ),
        now: created_at + 1
      )

      decision = store.uniqueness_decision(
        job: submission_job(
          id: 'job-1',
          created_at: created_at + 2,
          idempotency_key: 'submit-123',
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :active
        ),
        now: created_at + 3
      )

      expect(decision).to include(
        action: :reject,
        result: :duplicate_job_id,
        key_type: :job_id,
        key: 'job-1',
        conflicting_job_id: 'job-1'
      )
    end

    it 'reports duplicate idempotency before uniqueness conflicts' do
      store.enqueue(
        job: submission_job(
          id: 'job-1',
          created_at:,
          idempotency_key: 'submit-123',
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :active
        ),
        now: created_at + 1
      )

      decision = store.uniqueness_decision(
        job: submission_job(
          id: 'job-2',
          created_at: created_at + 2,
          idempotency_key: 'submit-123',
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :active
        ),
        now: created_at + 3
      )

      expect(decision).to include(
        action: :reject,
        result: :duplicate_idempotency_key,
        key_type: :idempotency_key,
        key: 'submit-123',
        conflicting_job_id: 'job-1'
      )
    end

    it 'reports duplicate uniqueness conflicts' do
      store.enqueue(
        job: submission_job(
          id: 'job-1',
          created_at:,
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :queued
        ),
        now: created_at + 1
      )

      decision = store.uniqueness_decision(
        job: submission_job(
          id: 'job-2',
          created_at: created_at + 2,
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :active
        ),
        now: created_at + 3
      )

      expect(decision).to include(
        action: :reject,
        result: :duplicate_uniqueness_key,
        key_type: :uniqueness_key,
        key: 'billing:account-42',
        conflicting_job_id: 'job-1',
        uniqueness_scope: :active
      )
    end

    it 'does not mutate due retry-pending jobs while computing a decision' do
      store.enqueue(
        job: submission_job(
          id: 'job-1',
          created_at:,
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :queued
        ),
        now: created_at + 1
      )
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 4,
        failure_classification: :error,
        retry_policy:
      )

      decision = store.uniqueness_decision(
        job: submission_job(
          id: 'job-2',
          created_at: created_at + 10,
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :queued
        ),
        now: created_at + 10
      )

      expect(decision).to include(result: :duplicate_uniqueness_key, conflicting_job_id: 'job-1')
    end

    it 'does not recover expired reserved leases while computing a decision' do
      store.enqueue(
        job: submission_job(
          id: 'job-1',
          created_at:,
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :queued
        ),
        now: created_at + 1
      )
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 2, now: created_at + 2)

      decision = store.uniqueness_decision(
        job: submission_job(
          id: 'job-2',
          created_at: created_at + 5,
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :active
        ),
        now: created_at + 5
      )

      expect(decision).to include(result: :duplicate_uniqueness_key, conflicting_job_id: 'job-1')
      expect do
        store.start_execution(reservation_token: reservation.token, now: created_at + 6)
      end.to raise_error(Karya::ExpiredReservationError)
    end
  end

  describe '#uniqueness_snapshot' do
    it 'includes idempotency blockers after terminal completion' do
      store.enqueue(
        job: submission_job(id: 'job-1', created_at:, idempotency_key: 'submit-123'),
        now: created_at + 1
      )
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.complete_execution(reservation_token: reservation.token, now: created_at + 4)

      snapshot = store.uniqueness_snapshot(now: created_at + 5)

      expect(snapshot[:idempotency_keys].fetch('submit-123')).to include(
        key: 'submit-123',
        job_id: 'job-1',
        queue: 'billing',
        handler: 'billing_sync',
        state: :succeeded,
        created_at:
      )
      expect_deep_frozen(snapshot)
    end

    it 'excludes expired queued uniqueness jobs without mutating them' do
      store.enqueue(
        job: submission_job(
          id: 'job-1',
          created_at:,
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :queued,
          expires_at: created_at + 2
        ),
        now: created_at + 1
      )

      snapshot = store.uniqueness_snapshot(now: created_at + 3)

      expect(snapshot[:uniqueness_keys]).to be_empty
    end

    it 'excludes terminal uniqueness jobs that no longer block incoming scopes' do
      store.enqueue(
        job: submission_job(
          id: 'job-1',
          created_at:,
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :active
        ),
        now: created_at + 1
      )
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.complete_execution(reservation_token: reservation.token, now: created_at + 4)

      snapshot = store.uniqueness_snapshot(now: created_at + 5)

      expect(snapshot[:uniqueness_keys]).to be_empty
    end

    it 'reports due retry-pending blockers as effectively queued without mutating them' do
      store.enqueue(
        job: submission_job(
          id: 'job-1',
          created_at:,
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :queued
        ),
        now: created_at + 1
      )
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 4,
        failure_classification: :error,
        retry_policy:
      )

      snapshot = store.uniqueness_snapshot(now: created_at + 10)
      blocker = snapshot[:uniqueness_keys].fetch('billing:account-42').first

      expect(blocker).to include(
        job_id: 'job-1',
        state: :retry_pending,
        effective_state: :queued,
        uniqueness_scope: :queued,
        blocked_incoming_scopes: %i[queued active until_terminal]
      )
    end

    it 'reports expired running blockers as effectively queued without mutating them' do
      store.enqueue(
        job: submission_job(
          id: 'job-1',
          created_at:,
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :active
        ),
        now: created_at + 1
      )
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 2, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)

      snapshot = store.uniqueness_snapshot(now: created_at + 6)
      blocker = snapshot[:uniqueness_keys].fetch('billing:account-42').first

      expect(blocker).to include(
        job_id: 'job-1',
        state: :running,
        effective_state: :queued,
        uniqueness_scope: :active,
        blocked_incoming_scopes: %i[queued active until_terminal]
      )
      expect do
        store.complete_execution(reservation_token: reservation.token, now: created_at + 7)
      end.to raise_error(Karya::ExpiredReservationError)
    end

    it 'reports asymmetric blocked incoming scopes for reserved queued-scope blockers' do
      store.enqueue(
        job: submission_job(
          id: 'job-1',
          created_at:,
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :queued
        ),
        now: created_at + 1
      )
      store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      snapshot = store.uniqueness_snapshot(now: created_at + 3)
      blocker = snapshot[:uniqueness_keys].fetch('billing:account-42').first

      expect(blocker).to include(
        state: :reserved,
        effective_state: :reserved,
        uniqueness_scope: :queued,
        blocked_incoming_scopes: %i[active until_terminal]
      )
    end
  end
end
