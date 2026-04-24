# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::InMemory do
  subject(:store) { described_class.new(token_generator: token_generator, policy_set:) }

  let(:token_sequence) { %w[lease-1 lease-2 lease-3 lease-4].each }
  let(:token_generator) { -> { token_sequence.next } }
  let(:created_at) { Time.utc(2026, 3, 27, 12, 0, 0) }
  let(:policy_set) { Karya::Backpressure::PolicySet.new }
  let(:tagged_string_class) { Class.new(String) }

  def submission_job(
    id:,
    queue:,
    created_at:,
    handler: 'billing_sync',
    priority: 0,
    concurrency_key: nil,
    rate_limit_key: nil,
    concurrency_scope: nil,
    rate_limit_scope: nil
  )
    Karya::Job.new(
      id:,
      queue:,
      handler:,
      priority:,
      concurrency_key:,
      rate_limit_key:,
      concurrency_scope:,
      rate_limit_scope:,
      state: :submission,
      created_at:
    )
  end

  describe '#reserve' do
    it 'returns nil when the queue is empty' do
      expect(
        store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 1)
      ).to be_nil
    end

    it 'only reserves from the requested queue' do
      store.enqueue(job: submission_job(id: 'billing-1', queue: 'billing', created_at:), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'email-1', queue: 'email', created_at:), now: created_at + 2)

      reservation = store.reserve(queue: 'email', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)

      expect(reservation.job_id).to eq('email-1')
      expect(
        store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 4).job_id
      ).to eq('billing-1')
    end

    it 'reserves jobs in FIFO order within the same queue' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'job-2', queue: 'billing', created_at:), now: created_at + 2)

      first = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)
      second = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 4)

      expect(first.job_id).to eq('job-1')
      expect(second.job_id).to eq('job-2')
    end

    it 'reserves higher priority jobs first within the same queue' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:, priority: 1), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'job-2', queue: 'billing', created_at: created_at + 1, priority: 10), now: created_at + 2)

      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)

      expect(reservation.job_id).to eq('job-2')
    end

    it 'keeps FIFO order for jobs with the same priority' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:, priority: 5), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'job-2', queue: 'billing', created_at: created_at + 1, priority: 5), now: created_at + 2)

      first = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)
      second = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 4)

      expect(first.job_id).to eq('job-1')
      expect(second.job_id).to eq('job-2')
    end

    it 'keeps queue order ahead of cross-queue priority' do
      store.enqueue(job: submission_job(id: 'billing-1', queue: 'billing', created_at:, priority: 1), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'email-1', queue: 'email', created_at: created_at + 1, priority: 99), now: created_at + 2)

      reservation = store.reserve(
        queues: %w[billing email],
        handler_names: %w[billing_sync],
        worker_id: 'worker-1',
        lease_duration: 30,
        now: created_at + 3
      )

      expect(reservation.job_id).to eq('billing-1')
    end

    it 'uses round-robin fairness by default across busy subscribed queues' do
      %w[1 2 3].each do |suffix|
        store.enqueue(job: submission_job(id: "billing-#{suffix}", queue: 'billing', created_at:), now: created_at + suffix.to_i)
        store.enqueue(job: submission_job(id: "email-#{suffix}", queue: 'email', created_at:), now: created_at + suffix.to_i + 3)
      end

      reserved_job_ids = Array.new(4) do |index|
        store.reserve(
          queues: %w[billing email],
          handler_names: %w[billing_sync],
          worker_id: "worker-#{index}",
          lease_duration: 30,
          now: created_at + 10 + index
        ).job_id
      end

      expect(reserved_job_ids).to eq(%w[billing-1 email-1 billing-2 email-2])
    end

    it 'does not advance round-robin fairness after a nil reservation' do
      store.enqueue(job: submission_job(id: 'billing-1', queue: 'billing', created_at:), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'email-1', queue: 'email', created_at:), now: created_at + 2)
      first = store.reserve(
        queues: %w[billing email],
        handler_names: %w[billing_sync],
        worker_id: 'worker-1',
        lease_duration: 30,
        now: created_at + 3
      )

      empty_result = store.reserve(
        queues: %w[reports],
        handler_names: %w[billing_sync],
        worker_id: 'worker-2',
        lease_duration: 30,
        now: created_at + 4
      )
      second = store.reserve(
        queues: %w[billing email],
        handler_names: %w[billing_sync],
        worker_id: 'worker-3',
        lease_duration: 30,
        now: created_at + 5
      )

      expect(first.job_id).to eq('billing-1')
      expect(empty_result).to be_nil
      expect(second.job_id).to eq('email-1')
    end

    it 'preserves fixed queue preference with strict-order fairness' do
      strict_store = described_class.new(
        token_generator: token_generator,
        fairness_policy: Karya::Fairness::Policy.new(strategy: :strict_order)
      )
      %w[1 2].each do |suffix|
        strict_store.enqueue(job: submission_job(id: "billing-#{suffix}", queue: 'billing', created_at:), now: created_at + suffix.to_i)
        strict_store.enqueue(job: submission_job(id: "email-#{suffix}", queue: 'email', created_at:), now: created_at + suffix.to_i + 2)
      end

      reserved_job_ids = Array.new(3) do |index|
        strict_store.reserve(
          queues: %w[billing email],
          handler_names: %w[billing_sync],
          worker_id: "worker-#{index}",
          lease_duration: 30,
          now: created_at + 10 + index
        ).job_id
      end

      expect(reserved_job_ids).to eq(%w[billing-1 billing-2 email-1])
    end

    it 'keeps round-robin fairness scoped to the subscribed queue list when unrelated reservations interleave' do
      %w[1 2].each do |suffix|
        store.enqueue(job: submission_job(id: "billing-#{suffix}", queue: 'billing', created_at:), now: created_at + suffix.to_i)
        store.enqueue(job: submission_job(id: "email-#{suffix}", queue: 'email', created_at:), now: created_at + suffix.to_i + 2)
      end
      store.enqueue(job: submission_job(id: 'reports-1', queue: 'reports', created_at:), now: created_at + 10)

      first = store.reserve(
        queues: %w[billing email],
        handler_names: %w[billing_sync],
        worker_id: 'worker-1',
        lease_duration: 30,
        now: created_at + 11
      )
      unrelated = store.reserve(
        queues: %w[reports],
        handler_names: %w[billing_sync],
        worker_id: 'worker-2',
        lease_duration: 30,
        now: created_at + 12
      )
      second = store.reserve(
        queues: %w[billing email],
        handler_names: %w[billing_sync],
        worker_id: 'worker-3',
        lease_duration: 30,
        now: created_at + 13
      )

      expect(first.job_id).to eq('billing-1')
      expect(unrelated.job_id).to eq('reports-1')
      expect(second.job_id).to eq('email-1')
    end

    it 'keeps round-robin fairness scoped to the full subscription when handler sets differ' do
      %w[1 2].each do |suffix|
        store.enqueue(
          job: submission_job(id: "billing-#{suffix}", queue: 'billing', created_at:, handler: 'billing_sync'),
          now: created_at + suffix.to_i
        )
        store.enqueue(
          job: submission_job(id: "email-#{suffix}", queue: 'email', created_at: created_at + suffix.to_i, handler: 'email_sync'),
          now: created_at + suffix.to_i + 2
        )
      end

      first = store.reserve(
        queues: %w[billing email],
        handler_names: %w[billing_sync email_sync],
        worker_id: 'worker-1',
        lease_duration: 30,
        now: created_at + 10
      )
      unrelated = store.reserve(
        queues: %w[billing email],
        handler_names: %w[email_sync],
        worker_id: 'worker-2',
        lease_duration: 30,
        now: created_at + 11
      )
      second = store.reserve(
        queues: %w[billing email],
        handler_names: %w[billing_sync email_sync],
        worker_id: 'worker-3',
        lease_duration: 30,
        now: created_at + 12
      )

      expect(first.job_id).to eq('billing-1')
      expect(unrelated.job_id).to eq('email-1')
      expect(second.job_id).to eq('email-2')
    end

    it 'keeps fairness state separate for queue lists whose names would collide under delimiter joining' do
      store.enqueue(job: submission_job(id: 'null-a-1', queue: "a\0b", created_at:), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'null-c-1', queue: 'c', created_at: created_at + 1), now: created_at + 2)
      store.enqueue(job: submission_job(id: 'plain-a-1', queue: 'a', created_at: created_at + 2), now: created_at + 3)
      store.enqueue(job: submission_job(id: 'null-bc-1', queue: "b\0c", created_at: created_at + 3), now: created_at + 4)

      first = store.reserve(
        queues: ["a\0b", 'c'],
        handler_names: %w[billing_sync],
        worker_id: 'worker-1',
        lease_duration: 30,
        now: created_at + 5
      )
      unrelated = store.reserve(
        queues: ['a', "b\0c"],
        handler_names: %w[billing_sync],
        worker_id: 'worker-2',
        lease_duration: 30,
        now: created_at + 6
      )
      second = store.reserve(
        queues: ["a\0b", 'c'],
        handler_names: %w[billing_sync],
        worker_id: 'worker-3',
        lease_duration: 30,
        now: created_at + 7
      )

      expect(first.job_id).to eq('null-a-1')
      expect(unrelated.job_id).to eq('plain-a-1')
      expect(second.job_id).to eq('null-c-1')
    end

    it 'bounds stored fairness history across many distinct queue lists' do
      token_index = 0
      bounded_store = described_class.new(
        token_generator: lambda {
          token_index += 1
          "lease-bounded-#{token_index}"
        },
        policy_set:
      )

      140.times do |index|
        primary_queue = "queue-#{index}"
        secondary_queue = "queue-shadow-#{index}"
        bounded_store.enqueue(job: submission_job(id: "job-#{index}", queue: primary_queue, created_at:), now: created_at + index + 1)
        bounded_store.enqueue(
          job: submission_job(id: "shadow-#{index}", queue: secondary_queue, created_at: created_at + index + 1),
          now: created_at + index + 2
        )
        expect(
          bounded_store.reserve(
            queues: [primary_queue, secondary_queue],
            worker_id: "worker-#{index}",
            lease_duration: 30,
            now: created_at + 200 + index
          )
        ).not_to be_nil
      end
    end

    it 'reserves first matching job from subscribed queues in declared order' do
      store.enqueue(job: submission_job(id: 'billing-1', queue: 'billing', created_at:, handler: 'billing_sync'), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'email-1', queue: 'email', created_at: created_at + 1, handler: 'email_sync'), now: created_at + 2)

      reservation = store.reserve(
        queues: %w[email billing],
        handler_names: %w[email_sync billing_sync],
        worker_id: 'worker-1',
        lease_duration: 30,
        now: created_at + 3
      )

      expect(reservation.job_id).to eq('email-1')
    end

    it 'accepts String subclasses for queue and worker_id' do
      store.enqueue(job: submission_job(id: 'billing-1', queue: 'billing', created_at:), now: created_at + 1)

      reservation = store.reserve(
        queue: tagged_string_class.new('billing'),
        worker_id: tagged_string_class.new('worker-1'),
        lease_duration: 30,
        now: created_at + 2
      )

      expect(reservation.job_id).to eq('billing-1')
      expect(reservation.worker_id).to eq('worker-1')
    end

    it 'skips unsupported handlers in same queue without mutating queued jobs' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:, handler: 'unsupported'), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'job-2', queue: 'billing', created_at: created_at + 1, handler: 'billing_sync'), now: created_at + 2)

      reservation = store.reserve(
        queues: ['billing'],
        handler_names: ['billing_sync'],
        worker_id: 'worker-1',
        lease_duration: 30,
        now: created_at + 3
      )

      expect(reservation.job_id).to eq('job-2')
      expect(store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 4).job_id).to eq('job-1')
    end

    it 'skips subscribed queues with only unsupported jobs and finds later matching queue' do
      store.enqueue(job: submission_job(id: 'billing-1', queue: 'billing', created_at:, handler: 'unsupported'), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'email-1', queue: 'email', created_at: created_at + 1, handler: 'email_sync'), now: created_at + 2)

      reservation = store.reserve(
        queues: %w[billing email],
        handler_names: ['email_sync'],
        worker_id: 'worker-1',
        lease_duration: 30,
        now: created_at + 3
      )

      expect(reservation.job_id).to eq('email-1')
      expect(store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 4).job_id).to eq('billing-1')
    end

    it 'skips paused queues and resumes fair rotation when the queue becomes eligible' do
      store.enqueue(job: submission_job(id: 'billing-1', queue: 'billing', created_at:), now: created_at + 1)
      store.enqueue(job: submission_job(id: 'email-1', queue: 'email', created_at:), now: created_at + 2)
      store.pause_queue(queue: 'billing', now: created_at + 3)

      first = store.reserve(
        queues: %w[billing email],
        handler_names: %w[billing_sync],
        worker_id: 'worker-1',
        lease_duration: 30,
        now: created_at + 4
      )
      store.resume_queue(queue: 'billing', now: created_at + 5)
      second = store.reserve(
        queues: %w[billing email],
        handler_names: %w[billing_sync],
        worker_id: 'worker-2',
        lease_duration: 30,
        now: created_at + 6
      )

      expect(first.job_id).to eq('email-1')
      expect(second.job_id).to eq('billing-1')
    end

    it 'returns nil when subscribed queues only contain unsupported handlers' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:, handler: 'unsupported'), now: created_at + 1)

      reservation = store.reserve(
        queues: ['billing'],
        handler_names: ['billing_sync'],
        worker_id: 'worker-1',
        lease_duration: 30,
        now: created_at + 2
      )

      expect(reservation).to be_nil
      expect(store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 3).job_id).to eq('job-1')
    end

    it 'skips blocked higher-priority jobs and reserves lower-priority eligible jobs' do
      constrained_store = described_class.new(
        token_generator: token_generator,
        policy_set: Karya::Backpressure::PolicySet.new(concurrency: { account_sync: { limit: 1 } })
      )
      constrained_store.enqueue(
        job: submission_job(id: 'job-1', queue: 'billing', created_at:, priority: 10, concurrency_key: 'account_sync'),
        now: created_at + 1
      )
      constrained_store.enqueue(
        job: submission_job(id: 'job-2', queue: 'billing', created_at: created_at + 1, priority: 9, concurrency_key: 'account_sync'),
        now: created_at + 2
      )
      constrained_store.enqueue(
        job: submission_job(id: 'job-3', queue: 'billing', created_at: created_at + 2, priority: 1),
        now: created_at + 3
      )

      first = constrained_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 4)
      second = constrained_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 5)

      expect(first.job_id).to eq('job-1')
      expect(second.job_id).to eq('job-3')
    end

    it 'skips blocked earlier queues and reserves from later queues' do
      constrained_store = described_class.new(
        token_generator: token_generator,
        policy_set: Karya::Backpressure::PolicySet.new(concurrency: { account_sync: { limit: 1 } })
      )
      constrained_store.enqueue(
        job: submission_job(id: 'billing-1', queue: 'billing', created_at:, priority: 10, concurrency_key: 'account_sync'),
        now: created_at + 1
      )
      constrained_store.enqueue(
        job: submission_job(id: 'billing-2', queue: 'billing', created_at: created_at + 1, priority: 9, concurrency_key: 'account_sync'),
        now: created_at + 2
      )
      constrained_store.enqueue(
        job: submission_job(id: 'email-1', queue: 'email', created_at: created_at + 2, priority: 1),
        now: created_at + 3
      )

      constrained_store.reserve(
        queues: %w[billing email],
        handler_names: %w[billing_sync],
        worker_id: 'worker-1',
        lease_duration: 30,
        now: created_at + 4
      )

      reservation = constrained_store.reserve(
        queues: %w[billing email],
        handler_names: %w[billing_sync],
        worker_id: 'worker-2',
        lease_duration: 30,
        now: created_at + 5
      )

      expect(reservation.job_id).to eq('email-1')
    end

    it 'skips circuit-breaker-blocked queues while preserving queued work' do
      breaker_store = described_class.new(
        token_generator: token_generator,
        circuit_breaker_policy_set: Karya::CircuitBreaker::PolicySet.new(
          policies: {
            'queue:billing' => { failure_threshold: 1, window: 60, cooldown: 30 }
          }
        ),
        fairness_policy: Karya::Fairness::Policy.new(strategy: :strict_order)
      )
      breaker_store.enqueue(job: submission_job(id: 'billing-1', queue: 'billing', created_at:), now: created_at + 1)
      breaker_store.enqueue(job: submission_job(id: 'billing-2', queue: 'billing', created_at: created_at + 1), now: created_at + 2)
      breaker_store.enqueue(job: submission_job(id: 'email-1', queue: 'email', created_at: created_at + 2), now: created_at + 3)

      first = breaker_store.reserve(queues: %w[billing email], worker_id: 'worker-1', lease_duration: 30, now: created_at + 4)
      breaker_store.start_execution(reservation_token: first.token, now: created_at + 5)
      breaker_store.fail_execution(reservation_token: first.token, now: created_at + 6, failure_classification: :error)
      second = breaker_store.reserve(queues: %w[billing email], worker_id: 'worker-2', lease_duration: 30, now: created_at + 7)
      expect(second.job_id).to eq('email-1')
      expect(breaker_store.reserve(queue: 'billing', worker_id: 'worker-3', lease_duration: 30, now: created_at + 40).job_id).to eq('billing-2')
    end

    it 'reopens concurrency capacity after release' do
      constrained_store = described_class.new(
        token_generator: token_generator,
        policy_set: Karya::Backpressure::PolicySet.new(concurrency: { account_sync: { limit: 1 } })
      )
      constrained_store.enqueue(
        job: submission_job(id: 'job-1', queue: 'billing', created_at:, concurrency_key: 'account_sync'),
        now: created_at + 1
      )
      constrained_store.enqueue(
        job: submission_job(id: 'job-2', queue: 'billing', created_at: created_at + 1, concurrency_key: 'account_sync'),
        now: created_at + 2
      )

      first = constrained_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)
      expect(constrained_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 4)).to be_nil

      constrained_store.release(reservation_token: first.token, now: created_at + 5)

      second = constrained_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 6)
      expect(second.job_id).to eq('job-2')
    end

    it 'reopens concurrency capacity after execution completion' do
      constrained_store = described_class.new(
        token_generator: token_generator,
        policy_set: Karya::Backpressure::PolicySet.new(concurrency: { account_sync: { limit: 1 } })
      )
      constrained_store.enqueue(
        job: submission_job(id: 'job-1', queue: 'billing', created_at:, concurrency_key: 'account_sync'),
        now: created_at + 1
      )
      constrained_store.enqueue(
        job: submission_job(id: 'job-2', queue: 'billing', created_at: created_at + 1, concurrency_key: 'account_sync'),
        now: created_at + 2
      )

      first = constrained_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)
      constrained_store.start_execution(reservation_token: first.token, now: created_at + 4)
      expect(constrained_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 5)).to be_nil

      constrained_store.complete_execution(reservation_token: first.token, now: created_at + 6)

      second = constrained_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 7)
      expect(second.job_id).to eq('job-2')
    end

    it 'reopens concurrency capacity after expiration' do
      constrained_store = described_class.new(
        token_generator: token_generator,
        policy_set: Karya::Backpressure::PolicySet.new(concurrency: { account_sync: { limit: 1 } })
      )
      constrained_store.enqueue(
        job: submission_job(id: 'job-1', queue: 'billing', created_at:, concurrency_key: 'account_sync'),
        now: created_at + 1
      )
      constrained_store.enqueue(
        job: submission_job(id: 'job-2', queue: 'billing', created_at: created_at + 1, concurrency_key: 'account_sync'),
        now: created_at + 2
      )

      constrained_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 1, now: created_at + 3)

      replacement = constrained_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 5)
      expect(replacement.job_id).to eq('job-2')
    end

    it 'ignores concurrency caps for jobs without a configured concurrency_key' do
      constrained_store = described_class.new(
        token_generator: token_generator,
        policy_set: Karya::Backpressure::PolicySet.new(concurrency: { account_sync: { limit: 1 } })
      )
      constrained_store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      constrained_store.enqueue(job: submission_job(id: 'job-2', queue: 'billing', created_at: created_at + 1), now: created_at + 2)

      first = constrained_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)
      second = constrained_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 4)

      expect(first.job_id).to eq('job-1')
      expect(second.job_id).to eq('job-2')
    end

    it 'ignores unconfigured concurrency keys during reserve scans' do
      constrained_store = described_class.new(
        token_generator: token_generator,
        policy_set: Karya::Backpressure::PolicySet.new(concurrency: { account_sync: { limit: 1 } })
      )
      constrained_store.enqueue(
        job: submission_job(id: 'job-1', queue: 'billing', created_at:, concurrency_key: 'unconfigured'),
        now: created_at + 1
      )

      reservation = constrained_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      expect(reservation.job_id).to eq('job-1')
    end

    it 'blocks reservations after a rate-limit window reaches capacity' do
      limited_store = described_class.new(
        token_generator: token_generator,
        policy_set: Karya::Backpressure::PolicySet.new(rate_limits: { partner_api: { limit: 1, period: 60 } })
      )
      limited_store.enqueue(
        job: submission_job(id: 'job-1', queue: 'billing', created_at:, rate_limit_key: 'partner_api'),
        now: created_at + 1
      )
      limited_store.enqueue(
        job: submission_job(id: 'job-2', queue: 'billing', created_at: created_at + 1, rate_limit_key: 'partner_api'),
        now: created_at + 2
      )

      first = limited_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)
      second = limited_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 4)

      expect(first.job_id).to eq('job-1')
      expect(second).to be_nil
    end

    it 'skips rate-limited higher-priority jobs and reserves a later eligible job' do
      limited_store = described_class.new(
        token_generator: token_generator,
        policy_set: Karya::Backpressure::PolicySet.new(rate_limits: { partner_api: { limit: 1, period: 60 } })
      )
      limited_store.enqueue(
        job: submission_job(id: 'job-1', queue: 'billing', created_at:, priority: 10, rate_limit_key: 'partner_api'),
        now: created_at + 1
      )
      limited_store.enqueue(
        job: submission_job(id: 'job-2', queue: 'billing', created_at: created_at + 1, priority: 9, rate_limit_key: 'partner_api'),
        now: created_at + 2
      )
      limited_store.enqueue(
        job: submission_job(id: 'job-3', queue: 'billing', created_at: created_at + 2, priority: 1),
        now: created_at + 3
      )

      first = limited_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 4)
      second = limited_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 5)

      expect(first.job_id).to eq('job-1')
      expect(second.job_id).to eq('job-3')
    end

    it 'reopens rate-limit capacity after the window expires' do
      limited_store = described_class.new(
        token_generator: token_generator,
        policy_set: Karya::Backpressure::PolicySet.new(rate_limits: { partner_api: { limit: 1, period: 10 } })
      )
      limited_store.enqueue(
        job: submission_job(id: 'job-1', queue: 'billing', created_at:, rate_limit_key: 'partner_api'),
        now: created_at + 1
      )
      limited_store.enqueue(
        job: submission_job(id: 'job-2', queue: 'billing', created_at: created_at + 1, rate_limit_key: 'partner_api'),
        now: created_at + 2
      )

      first = limited_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)
      expect(first.job_id).to eq('job-1')

      second = limited_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 14)
      expect(second.job_id).to eq('job-2')
    end

    it 'ignores rate limits for jobs without a configured rate_limit_key' do
      limited_store = described_class.new(
        token_generator: token_generator,
        policy_set: Karya::Backpressure::PolicySet.new(rate_limits: { partner_api: { limit: 1, period: 60 } })
      )
      limited_store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      limited_store.enqueue(job: submission_job(id: 'job-2', queue: 'billing', created_at: created_at + 1), now: created_at + 2)

      first = limited_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)
      second = limited_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 4)

      expect(first.job_id).to eq('job-1')
      expect(second.job_id).to eq('job-2')
    end

    it 'enforces queue-scoped concurrency policies from job routing metadata' do
      scoped_store = described_class.new(
        token_generator: token_generator,
        policy_set: Karya::Backpressure::PolicySet.new(
          concurrency: {
            { kind: :queue, value: 'billing' } => { limit: 1 }
          }
        )
      )
      scoped_store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      scoped_store.enqueue(job: submission_job(id: 'job-2', queue: 'billing', created_at: created_at + 1), now: created_at + 2)

      first = scoped_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)
      second = scoped_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 4)

      expect(first.job_id).to eq('job-1')
      expect(second).to be_nil
    end

    it 'enforces handler-scoped rate limits from job routing metadata' do
      scoped_store = described_class.new(
        token_generator: token_generator,
        policy_set: Karya::Backpressure::PolicySet.new(
          rate_limits: {
            { kind: :handler, value: 'billing_sync' } => { limit: 1, period: 60 }
          }
        )
      )
      scoped_store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:, handler: 'billing_sync'), now: created_at + 1)
      scoped_store.enqueue(job: submission_job(id: 'job-2', queue: 'billing', created_at: created_at + 1, handler: 'billing_sync'), now: created_at + 2)

      first = scoped_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)
      second = scoped_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 4)

      expect(first.job_id).to eq('job-1')
      expect(second).to be_nil
    end

    it 'enforces explicit tenant scopes across related jobs' do
      scoped_store = described_class.new(
        token_generator: token_generator,
        policy_set: Karya::Backpressure::PolicySet.new(
          concurrency: {
            { kind: :tenant, value: 'tenant-7' } => { limit: 1 }
          }
        )
      )
      scoped_store.enqueue(
        job: submission_job(
          id: 'job-1',
          queue: 'billing',
          created_at:,
          concurrency_scope: { kind: :tenant, value: 'tenant-7' }
        ),
        now: created_at + 1
      )
      scoped_store.enqueue(
        job: submission_job(
          id: 'job-2',
          queue: 'billing',
          created_at: created_at + 1,
          concurrency_scope: { kind: :tenant, value: 'tenant-7' }
        ),
        now: created_at + 2
      )

      first = scoped_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)
      second = scoped_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 4)

      expect(first.job_id).to eq('job-1')
      expect(second).to be_nil
    end

    it 'returns a read-only backpressure snapshot grouped by normalized scope keys' do
      scoped_store = described_class.new(
        token_generator: token_generator,
        policy_set: Karya::Backpressure::PolicySet.new(
          concurrency: {
            { kind: :queue, value: 'billing' } => { limit: 1 }
          },
          rate_limits: {
            { kind: :tenant, value: 'tenant-7' } => { limit: 1, period: 60 }
          }
        )
      )
      scoped_store.enqueue(
        job: submission_job(
          id: 'job-1',
          queue: 'billing',
          created_at:,
          rate_limit_scope: { kind: :tenant, value: 'tenant-7' }
        ),
        now: created_at + 1
      )
      scoped_store.enqueue(
        job: submission_job(
          id: 'job-2',
          queue: 'billing',
          created_at: created_at + 1,
          rate_limit_scope: { kind: :tenant, value: 'tenant-7' }
        ),
        now: created_at + 2
      )

      scoped_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 3)

      snapshot = scoped_store.backpressure_snapshot(now: created_at + 4)

      expect(snapshot).to be_frozen
      expect(snapshot[:captured_at]).to eq(created_at + 4)
      expect(snapshot[:captured_at]).to be_frozen
      expect(snapshot[:concurrency]).to be_frozen
      expect(snapshot[:rate_limits]).to be_frozen
      expect(snapshot[:concurrency].fetch('queue:billing')).to include(limit: 1, active_count: 1, blocked_count: 1)
      expect(snapshot[:rate_limits].fetch('tenant:tenant-7')).to include(limit: 1, window_count: 1, blocked_count: 1, period: 60)
      expect(snapshot[:concurrency].fetch('queue:billing')).to be_frozen
      expect(snapshot[:rate_limits].fetch('tenant:tenant-7')).to be_frozen
    end

    it 'ignores unconfigured explicit scopes in backpressure snapshots' do
      scoped_store = described_class.new(
        token_generator: token_generator,
        policy_set: Karya::Backpressure::PolicySet.new(
          concurrency: {
            { kind: :queue, value: 'billing' } => { limit: 1 }
          },
          rate_limits: {
            { kind: :handler, value: 'billing_sync' } => { limit: 1, period: 60 }
          }
        )
      )
      scoped_store.enqueue(
        job: submission_job(
          id: 'job-1',
          queue: 'billing',
          created_at:,
          concurrency_scope: { kind: :tenant, value: 'tenant-7' },
          rate_limit_scope: { kind: :workflow, value: 'nightly-billing' }
        ),
        now: created_at + 1
      )

      snapshot = scoped_store.backpressure_snapshot(now: created_at + 2)

      expect(snapshot[:concurrency].fetch('queue:billing')).to include(active_count: 0, blocked_count: 0)
      expect(snapshot[:rate_limits].fetch('handler:billing_sync')).to include(window_count: 0, blocked_count: 0)
    end

    it 'runs maintenance before building backpressure snapshots' do
      scoped_store = described_class.new(
        token_generator: token_generator,
        policy_set: Karya::Backpressure::PolicySet.new(
          concurrency: {
            { kind: :queue, value: 'billing' } => { limit: 1 }
          }
        )
      )
      scoped_store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      scoped_store.enqueue(job: submission_job(id: 'job-2', queue: 'billing', created_at: created_at + 1), now: created_at + 2)

      scoped_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 1, now: created_at + 3)

      snapshot = scoped_store.backpressure_snapshot(now: created_at + 5)

      expect(snapshot[:concurrency].fetch('queue:billing')).to include(active_count: 0, blocked_count: 0)
      expect(scoped_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 6).job_id).to eq('job-2')
      expect(scoped_store.reserve(queue: 'billing', worker_id: 'worker-3', lease_duration: 30, now: created_at + 7)).to be_nil
    end

    it 'does not promote due retry_pending jobs while building backpressure snapshots' do
      retry_policy = Karya::RetryPolicy.new(max_attempts: 3, base_delay: 5, multiplier: 2)
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      store.start_execution(reservation_token: reservation.token, now: created_at + 3)
      store.fail_execution(
        reservation_token: reservation.token,
        now: created_at + 4,
        retry_policy: retry_policy,
        failure_classification: :error
      )

      snapshot = store.backpressure_snapshot(now: created_at + 9)

      expect(snapshot[:concurrency]).to eq({})
      expect(store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 8)).to be_nil
    end

    it 'ignores unconfigured rate-limit keys without recording admissions' do
      store.enqueue(
        job: submission_job(id: 'job-1', queue: 'billing', created_at:, rate_limit_key: 'unconfigured'),
        now: created_at + 1
      )

      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      expect(reservation.job_id).to eq('job-1')
    end

    it 'returns a reservation lease with the reserved job metadata' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)

      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      expect(reservation).to be_a(Karya::Reservation)
      expect(reservation.token).to eq('lease-1:1')
      expect(reservation.job_id).to eq('job-1')
      expect(reservation.queue).to eq('billing')
      expect(reservation.worker_id).to eq('worker-1')
      expect(reservation.reserved_at).to eq(created_at + 2)
      expect(reservation.expires_at).to eq(created_at + 32)
    end

    it 'generates unique reservation tokens from repeated base token values without orphaning jobs' do
      token_sequence = %w[dup-token dup-token token-3 token-4].each
      duplicate_token_store = described_class.new(token_generator: -> { token_sequence.next })
      duplicate_token_store.enqueue(
        job: submission_job(id: 'job-1', queue: 'billing', created_at:),
        now: created_at + 1
      )
      duplicate_token_store.enqueue(
        job: submission_job(id: 'job-2', queue: 'billing', created_at: created_at + 1),
        now: created_at + 2
      )

      first_reservation = duplicate_token_store.reserve(
        queue: 'billing',
        worker_id: 'worker-1',
        lease_duration: 30,
        now: created_at + 3
      )
      second_reservation = duplicate_token_store.reserve(
        queue: 'billing',
        worker_id: 'worker-2',
        lease_duration: 30,
        now: created_at + 4
      )

      duplicate_token_store.release(reservation_token: first_reservation.token, now: created_at + 5)

      next_reservation = duplicate_token_store.reserve(
        queue: 'billing',
        worker_id: 'worker-3',
        lease_duration: 30,
        now: created_at + 6
      )
      duplicate_token_store.release(reservation_token: second_reservation.token, now: created_at + 7)
      reclaimed_reservation = duplicate_token_store.reserve(
        queue: 'billing',
        worker_id: 'worker-4',
        lease_duration: 30,
        now: created_at + 8
      )

      expect(second_reservation.token).to eq('dup-token:2')
      expect(second_reservation.token).not_to eq(first_reservation.token)
      expect(next_reservation.job_id).to eq('job-1')
      expect(reclaimed_reservation.job_id).to eq('job-2')
    end

    it 'expires leases before reserving so reclaimed jobs can be reused deterministically' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)
      store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)

      reservation = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 33)

      expect(reservation.job_id).to eq('job-1')
      expect(reservation.token).to eq('lease-2:2')
    end

    it 'rejects non-positive lease durations' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)

      expect do
        store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 0, now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /lease_duration must be a positive number/)
    end

    it 'rejects non-finite lease durations without removing the queued job' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)

      expect do
        store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: Float::INFINITY, now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /lease_duration must be a positive number/)

      reservation = store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 30, now: created_at + 3)
      expect(reservation.job_id).to eq('job-1')
    end

    it 'rejects unsupported numeric lease durations' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)

      expect do
        store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: Complex(1, 0), now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /lease_duration must be a positive number/)
    end

    it 'accepts Rational lease durations' do
      store.enqueue(job: submission_job(id: 'job-1', queue: 'billing', created_at:), now: created_at + 1)

      reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: Rational(3, 2), now: created_at + 2)

      expect(reservation.expires_at).to eq(created_at + Rational(7, 2))
    end

    it 'rejects blank identifiers for reserve input' do
      expect do
        store.reserve(queue: ' ', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /queue must be present/)
    end

    it 'rejects blank worker_id for reserve input' do
      expect do
        store.reserve(queue: 'billing', worker_id: ' ', lease_duration: 30, now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /worker_id must be present/)
    end

    it 'rejects nil worker_id for reserve input' do
      expect do
        store.reserve(queue: 'billing', worker_id: nil, lease_duration: 30, now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /worker_id must be present/)
    end

    it 'rejects non-string identifiers for reserve input' do
      expect do
        store.reserve(queue: 123, worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /queue must be a String/)

      expect do
        store.reserve(queue: 'billing', worker_id: 123, lease_duration: 30, now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /worker_id must be a String/)

      expect do
        store.reserve(queues: [123], worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /queues entries must be Strings/)
    end

    it 'rejects invalid timestamps for reserve input' do
      expect do
        store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: '2026-03-27T12:00:02Z')
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /now must be a Time/)
    end

    it 'rejects empty handler_names for subscription-aware reserve input' do
      expect do
        store.reserve(queues: ['billing'], handler_names: [], worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /handler_names must be present/)
    end

    it 'rejects non-array handler_names for subscription-aware reserve input' do
      expect do
        store.reserve(queues: ['billing'], handler_names: 'billing_sync', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /handler_names must be an Array/)
    end

    it 'rejects non-string handler names for subscription-aware reserve input' do
      expect do
        store.reserve(queues: ['billing'], handler_names: [123], worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /handler_names entries must be Strings/)
    end

    it 'rejects reserve input that provides both queue and queues' do
      expect do
        store.reserve(
          queue: 'billing',
          queues: ['billing'],
          worker_id: 'worker-1',
          lease_duration: 30,
          now: created_at + 2
        )
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /provide exactly one of queue or queues/)
    end

    it 'rejects reserve input that provides neither queue nor queues' do
      expect do
        store.reserve(worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /provide exactly one of queue or queues/)
    end
  end
end
