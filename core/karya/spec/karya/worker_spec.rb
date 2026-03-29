# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Worker do
  subject(:worker) do
    described_class.new(
      queue_store:,
      worker_id: 'worker-1',
      queues: queues,
      handlers:,
      lease_duration: 30,
      clock: -> { now },
      sleeper:
    )
  end

  let(:queue_store) { Karya::InMemoryQueueStore.new(token_generator: -> { 'lease-token' }) }
  let(:queues) { ['billing'] }
  let(:handlers) { { 'billing_sync' => handler } }
  let(:handler) { ->(**) {} }
  let(:now) { Time.utc(2026, 3, 29, 12, 0, 0) }
  let(:sleeper) { ->(_duration) {} }

  def submission_job(id:, queue: 'billing', handler_name: 'billing_sync', arguments: {})
    Karya::Job.new(
      id:,
      queue:,
      handler: handler_name,
      arguments:,
      state: :submission,
      created_at: now - 60
    )
  end

  def stored_job(id)
    queue_store.instance_variable_get(:@state).jobs_by_id.fetch(id)
  end

  describe '#work_once' do
    it 'executes a registered callable handler and persists succeeded state' do
      received_arguments = nil
      queue_store.enqueue(
        job: submission_job(id: 'job-1', arguments: { account_id: 42 }),
        now:
      )
      callable_handler = ->(**arguments) { received_arguments = arguments }
      callable_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers: { 'billing_sync' => callable_handler },
        lease_duration: 30,
        clock: -> { now }
      )

      result = callable_worker.work_once

      expect(received_arguments).to eq(account_id: 42)
      expect(result.state).to eq(:succeeded)
      expect(stored_job('job-1').state).to eq(:succeeded)
      expect(stored_job('job-1').attempt).to eq(1)
    end

    it 'executes handlers that implement perform' do
      performer = Class.new do
        class << self
          attr_reader :seen_arguments

          def perform(**arguments)
            @seen_arguments = arguments
          end
        end
      end
      queue_store.enqueue(
        job: submission_job(id: 'job-1', arguments: { account_id: 42 }),
        now:
      )
      perform_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers: { 'billing_sync' => performer },
        lease_duration: 30,
        clock: -> { now }
      )

      result = perform_worker.work_once

      expect(performer.seen_arguments).to eq(account_id: 42)
      expect(result.state).to eq(:succeeded)
    end

    it 'marks jobs failed when the handler is not registered' do
      queue_store.enqueue(
        job: submission_job(id: 'job-1', handler_name: 'missing_handler'),
        now:
      )

      result = worker.work_once

      expect(result.state).to eq(:failed)
      expect(stored_job('job-1').state).to eq(:failed)
      expect(stored_job('job-1').attempt).to eq(1)
    end

    it 'marks jobs failed when the handler raises' do
      queue_store.enqueue(
        job: submission_job(id: 'job-1'),
        now:
      )
      raising_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers: { 'billing_sync' => ->(**) { raise 'boom' } },
        lease_duration: 30,
        clock: -> { now }
      )

      result = raising_worker.work_once

      expect(result.state).to eq(:failed)
      expect(stored_job('job-1').state).to eq(:failed)
    end

    it 'marks jobs failed when the registered handler does not implement call or perform' do
      queue_store.enqueue(
        job: submission_job(id: 'job-1'),
        now:
      )
      invalid_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers: { 'billing_sync' => Object.new },
        lease_duration: 30,
        clock: -> { now }
      )

      result = invalid_worker.work_once

      expect(result.state).to eq(:failed)
      expect(stored_job('job-1').state).to eq(:failed)
    end

    it 'returns nil when subscribed queues have no work' do
      expect(worker.work_once).to be_nil
    end

    it 'checks subscribed queues in order' do
      queue_store.enqueue(job: submission_job(id: 'job-1', queue: 'email'), now:)
      ordered_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues: %w[billing email],
        handlers: { 'billing_sync' => ->(**) {} },
        lease_duration: 30,
        clock: -> { now }
      )

      result = ordered_worker.work_once

      expect(result.id).to eq('job-1')
      expect(result.state).to eq(:succeeded)
    end
  end

  describe 'configuration validation' do
    it 'configuration extraction requires the worker config keys' do
      expect do
        described_class::Configuration.from_options(worker_id: 'worker-1')
      end.to raise_error(ArgumentError)
    end

    it 'rejects blank worker ids' do
      expect do
        described_class.new(
          queue_store:,
          worker_id: ' ',
          queues:,
          handlers:,
          lease_duration: 30
        )
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /worker_id must be present/)
    end

    it 'rejects empty queue lists' do
      expect do
        described_class.new(
          queue_store:,
          worker_id: 'worker-1',
          queues: [],
          handlers:,
          lease_duration: 30
        )
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /queues must be present/)
    end

    it 'rejects non-hash handlers' do
      expect do
        described_class.new(
          queue_store:,
          worker_id: 'worker-1',
          queues:,
          handlers: [],
          lease_duration: 30
        )
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /handlers must be a Hash/)
    end

    it 'rejects non-positive lease durations' do
      expect do
        described_class.new(
          queue_store:,
          worker_id: 'worker-1',
          queues:,
          handlers:,
          lease_duration: 0
        )
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /lease_duration must be a positive finite number/)
    end

    it 'rejects clocks that do not respond to call' do
      expect do
        described_class.new(
          queue_store:,
          worker_id: 'worker-1',
          queues:,
          handlers:,
          lease_duration: 30,
          clock: Object.new
        )
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /clock must respond to #call/)
    end

    it 'rejects unknown runtime dependency keywords' do
      expect do
        described_class.new(
          queue_store:,
          worker_id: 'worker-1',
          queues:,
          handlers:,
          lease_duration: 30,
          tracer: Object.new
        )
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /unknown runtime dependency keywords: tracer/)
    end
  end

  describe '#run' do
    it 'stops cleanly when asked to stop on idle' do
      expect(worker.run(stop_when_idle: true)).to be_nil
    end

    it 'does not sleep after an iteration that executed work' do
      calls = []
      queue_store.enqueue(job: submission_job(id: 'job-1'), now:)
      running_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers:,
        lease_duration: 30,
        clock: -> { now },
        sleeper: ->(duration) { calls << duration }
      )

      result = running_worker.run(poll_interval: 2, stop_when_idle: true)

      expect(result).to be_nil
      expect(stored_job('job-1').state).to eq(:succeeded)
      expect(calls).to eq([])
    end

    it 'sleeps between idle polling attempts' do
      calls = []
      sleeping_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers:,
        lease_duration: 30,
        clock: -> { now },
        sleeper: ->(duration) { calls << duration }
      )

      sleeping_worker.run(poll_interval: 2, max_iterations: 3)

      expect(calls).to eq([2, 2])
    end

    it 'rejects negative poll intervals' do
      expect do
        worker.run(poll_interval: -1, max_iterations: 1)
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /poll_interval must be a finite non-negative number/)
    end

    it 'rejects non-positive max_iterations' do
      expect do
        worker.run(max_iterations: 0)
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /max_iterations must be a positive Integer/)
    end

    it 'rejects non-integer max_iterations' do
      expect do
        worker.run(max_iterations: 1.5)
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /max_iterations must be a positive Integer/)
    end

    it 'rejects clocks that return non-Time values' do
      bad_clock_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers:,
        lease_duration: 30,
        clock: -> { 'not-a-time' }
      )

      expect do
        bad_clock_worker.work_once
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /clock must return a Time/)
    end
  end
end
