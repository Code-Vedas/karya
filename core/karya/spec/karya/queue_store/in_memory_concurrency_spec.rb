# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::InMemory do
  subject(:store) { described_class.new(token_generator: token_generator) }

  let(:token_sequence) { %w[lease-1 lease-2 lease-3 lease-4 lease-5].each }
  let(:token_generator) { -> { token_sequence.next } }
  let(:created_at) { Time.utc(2026, 3, 28, 12, 0, 0) }

  def concurrent_results(thread_count)
    start_queue = Queue.new
    results = Queue.new

    threads = Array.new(thread_count) do |index|
      Thread.new do
        start_queue.pop
        result = yield(index)
        results << [:ok, result]
      rescue StandardError => e
        results << [:error, e.class]
      end
    end

    thread_count.times { start_queue << true }
    threads.each(&:join)
    Array.new(thread_count) { results.pop }
  end

  it 'serializes concurrent duplicate uniqueness enqueues' do
    results = concurrent_results(2) do |index|
      store.enqueue(
        job: Karya::Job.new(
          id: "job-#{index + 1}",
          queue: 'billing',
          handler: 'billing_sync',
          uniqueness_key: 'billing:account-42',
          uniqueness_scope: :active,
          state: :submission,
          created_at:
        ),
        now: created_at + 1
      )
    end

    expect(results.count { |status, _| status == :ok }).to eq(1)
    expect(results.count { |status, error| status == :error && error == Karya::DuplicateUniquenessKeyError }).to eq(1)
  end

  it 'serializes concurrent duplicate idempotency enqueues' do
    results = concurrent_results(2) do |index|
      store.enqueue(
        job: Karya::Job.new(
          id: "job-#{index + 1}",
          queue: 'billing',
          handler: 'billing_sync',
          idempotency_key: 'submit-123',
          state: :submission,
          created_at:
        ),
        now: created_at + 1
      )
    end

    expect(results.count { |status, _| status == :ok }).to eq(1)
    expect(results.count { |status, error| status == :error && error == Karya::DuplicateIdempotencyKeyError }).to eq(1)
  end

  it 'keeps uniqueness outcomes coherent across concurrent completion and enqueue' do
    store.enqueue(
      job: Karya::Job.new(
        id: 'job-1',
        queue: 'billing',
        handler: 'billing_sync',
        uniqueness_key: 'billing:account-42',
        uniqueness_scope: :active,
        state: :submission,
        created_at:
      ),
      now: created_at + 1
    )
    reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 30, now: created_at + 2)
    store.start_execution(reservation_token: reservation.token, now: created_at + 3)

    results = concurrent_results(2) do |index|
      if index.zero?
        store.complete_execution(reservation_token: reservation.token, now: created_at + 4)
      else
        store.enqueue(
          job: Karya::Job.new(
            id: 'job-2',
            queue: 'billing',
            handler: 'billing_sync',
            uniqueness_key: 'billing:account-42',
            uniqueness_scope: :active,
            state: :submission,
            created_at: created_at + 4
          ),
          now: created_at + 4
        )
      end
    end

    enqueue_outcomes = results.select { |status, value| status == :ok || value == Karya::DuplicateUniquenessKeyError }
    expect(enqueue_outcomes.length).to eq(2)

    job_states = store.instance_variable_get(:@state).jobs_by_id.transform_values(&:state)
    expect(job_states.values.count(:queued)).to be <= 1
    expect(job_states.values.count(:running)).to eq(0)
  end
end
