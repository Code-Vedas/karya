# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::InMemory do
  subject(:store) do
    described_class.new(
      token_generator: token_generator,
      circuit_breaker_policy_set: circuit_breaker_policy_set
    )
  end

  let(:token_sequence) { %w[lease-1 lease-2 lease-3 lease-4 lease-5 lease-6].each }
  let(:token_generator) { -> { token_sequence.next } }
  let(:created_at) { Time.utc(2026, 4, 8, 12, 0, 0) }
  let(:circuit_breaker_policy_set) { Karya::CircuitBreaker::PolicySet.new }

  def submission_job(id:, created_at:, queue: 'billing', handler: 'billing_sync', priority: 0)
    Karya::Job.new(
      id:,
      queue:,
      handler:,
      priority:,
      state: :submission,
      created_at:
    )
  end

  def reserve_and_start(job_id:, worker_id:, now:, lease_duration: 30)
    reservation = store.reserve(queue: 'billing', worker_id:, lease_duration:, now:)
    expect(reservation&.job_id).to eq(job_id)
    store.start_execution(reservation_token: reservation.token, now: now + 0.5)
    reservation
  end

  describe 'circuit breaking' do
    let(:circuit_breaker_policy_set) do
      Karya::CircuitBreaker::PolicySet.new(
        policies: {
          'queue:billing' => {
            failure_threshold: 2,
            window: 60,
            cooldown: 10
          }
        }
      )
    end

    it 'opens a breaker after repeated error failures within the window and blocks later reservations' do
      %w[job-1 job-2 job-3].each_with_index do |job_id, index|
        store.enqueue(job: submission_job(id: job_id, created_at: created_at + index), now: created_at + index)
      end

      first = reserve_and_start(job_id: 'job-1', worker_id: 'worker-1', now: created_at + 1)
      second = reserve_and_start(job_id: 'job-2', worker_id: 'worker-2', now: created_at + 3)

      store.fail_execution(reservation_token: first.token, now: created_at + 2, failure_classification: :error)
      store.fail_execution(reservation_token: second.token, now: created_at + 4, failure_classification: :error)

      expect(store.reserve(queue: 'billing', worker_id: 'worker-3', lease_duration: 30, now: created_at + 5)).to be_nil

      snapshot = store.reliability_snapshot(now: created_at + 5)
      breaker = snapshot[:circuit_breakers].fetch('queue:billing')

      expect(breaker).to include(
        state: :open,
        failure_count: 2,
        blocked_count: 1,
        cooldown_until: created_at + 14
      )
    end

    it 'opens a breaker after repeated timeout failures' do
      %w[job-1 job-2 job-3].each_with_index do |job_id, index|
        store.enqueue(job: submission_job(id: job_id, created_at: created_at + index), now: created_at + index)
      end

      first = reserve_and_start(job_id: 'job-1', worker_id: 'worker-1', now: created_at + 1)
      second = reserve_and_start(job_id: 'job-2', worker_id: 'worker-2', now: created_at + 3)

      store.fail_execution(reservation_token: first.token, now: created_at + 2, failure_classification: :timeout)
      store.fail_execution(reservation_token: second.token, now: created_at + 4, failure_classification: :timeout)

      expect(store.reserve(queue: 'billing', worker_id: 'worker-3', lease_duration: 30, now: created_at + 5)).to be_nil
    end

    it 'does not open a breaker for expired failures' do
      store.enqueue(job: submission_job(id: 'job-1', created_at: created_at), now: created_at)
      store.enqueue(job: submission_job(id: 'job-2', created_at: created_at + 1), now: created_at + 1)

      reservation = reserve_and_start(job_id: 'job-1', worker_id: 'worker-1', now: created_at + 2)
      store.fail_execution(reservation_token: reservation.token, now: created_at + 3, failure_classification: :expired)

      expect(store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 4)&.job_id).to eq('job-2')
      expect(store.reliability_snapshot(now: created_at + 4)[:circuit_breakers].fetch('queue:billing')).to include(state: :closed)
    end

    it 'keeps a configured breaker closed after a normal success' do
      store.enqueue(job: submission_job(id: 'job-1', created_at: created_at), now: created_at)

      reservation = reserve_and_start(job_id: 'job-1', worker_id: 'worker-1', now: created_at + 1)
      store.complete_execution(reservation_token: reservation.token, now: created_at + 2)

      expect(store.reliability_snapshot(now: created_at + 2)[:circuit_breakers].fetch('queue:billing')).to include(
        state: :closed,
        blocked_count: 0
      )
    end

    it 'reopens a breaker when a half-open probe fails' do
      threshold_one = Karya::CircuitBreaker::PolicySet.new(
        policies: {
          'queue:billing' => {
            failure_threshold: 1,
            window: 60,
            cooldown: 5
          }
        }
      )
      store = described_class.new(token_generator: token_generator, circuit_breaker_policy_set: threshold_one)

      %w[job-1 job-2 job-3].each_with_index do |job_id, index|
        store.enqueue(job: submission_job(id: job_id, created_at: created_at + index), now: created_at + index)
      end

      first = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 1)
      store.start_execution(reservation_token: first.token, now: created_at + 1.5)
      store.fail_execution(reservation_token: first.token, now: created_at + 2, failure_classification: :error)

      probe = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 8)
      expect(probe&.job_id).to eq('job-2')
      store.start_execution(reservation_token: probe.token, now: created_at + 8.5)
      store.fail_execution(reservation_token: probe.token, now: created_at + 9, failure_classification: :error)

      expect(store.reserve(queue: 'billing', worker_id: 'worker-3', lease_duration: 30, now: created_at + 10)).to be_nil
      expect(store.reliability_snapshot(now: created_at + 10)[:circuit_breakers].fetch('queue:billing')).to include(state: :open)
    end

    it 'closes a breaker when a half-open probe succeeds' do
      threshold_one = Karya::CircuitBreaker::PolicySet.new(
        policies: {
          'queue:billing' => {
            failure_threshold: 1,
            window: 60,
            cooldown: 5
          }
        }
      )
      store = described_class.new(token_generator: token_generator, circuit_breaker_policy_set: threshold_one)

      %w[job-1 job-2 job-3].each_with_index do |job_id, index|
        store.enqueue(job: submission_job(id: job_id, created_at: created_at + index), now: created_at + index)
      end

      first = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 1)
      store.start_execution(reservation_token: first.token, now: created_at + 1.5)
      store.fail_execution(reservation_token: first.token, now: created_at + 2, failure_classification: :error)

      probe = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 8)
      expect(probe&.job_id).to eq('job-2')
      store.start_execution(reservation_token: probe.token, now: created_at + 8.5)
      store.complete_execution(reservation_token: probe.token, now: created_at + 9)

      next_reservation = store.reserve(queue: 'billing', worker_id: 'worker-3', lease_duration: 30, now: created_at + 10)
      expect(next_reservation&.job_id).to eq('job-3')
      expect(store.reliability_snapshot(now: created_at + 10)[:circuit_breakers].fetch('queue:billing')).to include(
        state: :closed,
        failure_count: 0
      )
    end
  end

  describe 'stuck-job detection and reliability snapshots' do
    it 'tracks stuck jobs after running lease recovery and returns a frozen snapshot' do
      store.enqueue(job: submission_job(id: 'job-1', created_at: created_at), now: created_at)

      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 1, now: created_at + 1)
      store.start_execution(reservation_token: reservation.token, now: created_at + 1.5)

      snapshot = store.reliability_snapshot(now: created_at + 4)
      stuck_job = snapshot[:stuck_jobs].fetch('job-1')

      expect(snapshot).to be_frozen
      expect(snapshot[:circuit_breakers]).to be_frozen
      expect(snapshot[:stuck_jobs]).to be_frozen
      expect(stuck_job).to be_frozen
      expect(stuck_job).to include(
        job_id: 'job-1',
        queue: 'billing',
        handler: 'billing_sync',
        state: :queued,
        attempt: 1,
        recovery_count: 1,
        last_recovered_at: created_at + 4,
        last_recovery_reason: 'running_lease_expired'
      )
    end

    it 'increments recovery_count across repeated running-lease recoveries' do
      store.enqueue(job: submission_job(id: 'job-1', created_at: created_at), now: created_at)

      first = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 1, now: created_at + 1)
      store.start_execution(reservation_token: first.token, now: created_at + 1.5)
      store.reliability_snapshot(now: created_at + 4)

      second = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 1, now: created_at + 5)
      store.start_execution(reservation_token: second.token, now: created_at + 5.5)
      snapshot = store.reliability_snapshot(now: created_at + 8)

      expect(snapshot[:stuck_jobs].fetch('job-1')).to include(recovery_count: 2, last_recovered_at: created_at + 8)
    end

    it 'clears stuck-job metadata after a later success' do
      store.enqueue(job: submission_job(id: 'job-1', created_at: created_at), now: created_at)

      first = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 1, now: created_at + 1)
      store.start_execution(reservation_token: first.token, now: created_at + 1.5)
      store.reliability_snapshot(now: created_at + 4)

      second = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 5)
      store.start_execution(reservation_token: second.token, now: created_at + 5.5)
      store.complete_execution(reservation_token: second.token, now: created_at + 6)

      expect(store.reliability_snapshot(now: created_at + 7)[:stuck_jobs]).to eq({})
    end

    it 'does not classify reserved-lease recovery as a stuck-job detection' do
      store.enqueue(job: submission_job(id: 'job-1', created_at: created_at), now: created_at)

      store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 1, now: created_at + 1)

      expect(store.reliability_snapshot(now: created_at + 4)[:stuck_jobs]).to eq({})
    end
  end
end
