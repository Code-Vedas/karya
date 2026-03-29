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
  let(:handler) { -> {} }
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
      callable_handler = ->(account_id:) { received_arguments = { account_id: } }
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

          def perform(account_id:)
            @seen_arguments = { account_id: }
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

    it 'executes registered callable handlers that accept one positional hash argument' do
      received_arguments = nil
      queue_store.enqueue(
        job: submission_job(id: 'job-1', arguments: { account_id: 42 }),
        now:
      )
      positional_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers: { 'billing_sync' => ->(arguments) { received_arguments = arguments } },
        lease_duration: 30,
        clock: -> { now }
      )

      result = positional_worker.work_once

      expect(received_arguments).to eq('account_id' => 42)
      expect(result.state).to eq(:succeeded)
    end

    it 'executes class-based call handlers' do
      callable_handler = Class.new do
        class << self
          attr_reader :seen_arguments

          def call(account_id:)
            @seen_arguments = { account_id: }
          end
        end
      end
      queue_store.enqueue(
        job: submission_job(id: 'job-1', arguments: { account_id: 42 }),
        now:
      )
      callable_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers: { 'billing_sync' => callable_handler },
        lease_duration: 30,
        clock: -> { now }
      )

      result = callable_worker.work_once

      expect(callable_handler.seen_arguments).to eq(account_id: 42)
      expect(result.state).to eq(:succeeded)
    end

    it 'executes callable handlers that define an unrelated parameters method' do
      callable_handler = Class.new do
        class << self
          attr_reader :seen_arguments

          def call(account_id:)
            @seen_arguments = { account_id: }
          end

          def parameters
            []
          end
        end
      end
      queue_store.enqueue(
        job: submission_job(id: 'job-1', arguments: { account_id: 42 }),
        now:
      )
      callable_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers: { 'billing_sync' => callable_handler },
        lease_duration: 30,
        clock: -> { now }
      )

      result = callable_worker.work_once

      expect(callable_handler.seen_arguments).to eq(account_id: 42)
      expect(result.state).to eq(:succeeded)
    end

    it 'executes perform handlers that accept no arguments' do
      performer = Class.new do
        class << self
          attr_reader :called

          def perform
            @called = true
          end
        end
      end
      queue_store.enqueue(job: submission_job(id: 'job-1'), now:)
      perform_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers: { 'billing_sync' => performer },
        lease_duration: 30,
        clock: -> { now }
      )

      result = perform_worker.work_once

      expect(performer.called).to be(true)
      expect(result.state).to eq(:succeeded)
    end

    it 'executes perform handlers that accept one positional hash argument' do
      performer = Class.new do
        class << self
          attr_reader :seen_arguments

          def perform(arguments)
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

      expect(performer.seen_arguments).to eq('account_id' => 42)
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
        handlers: { 'billing_sync' => -> { raise 'boom' } },
        lease_duration: 30,
        clock: -> { now }
      )

      result = raising_worker.work_once

      expect(result.state).to eq(:failed)
      expect(stored_job('job-1').state).to eq(:failed)
    end

    it 'marks jobs failed when the handler raises UnknownReservationError' do
      queue_store.enqueue(
        job: submission_job(id: 'job-1'),
        now:
      )
      raising_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers: {
          'billing_sync' => -> { raise Karya::UnknownReservationError, 'handler error should not look like lease loss' }
        },
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

    it 'treats start_execution lease expiry as a no-op iteration instead of crashing' do
      time_points = [
        Time.utc(2026, 3, 29, 12, 0, 0),
        Time.utc(2026, 3, 29, 12, 0, 2)
      ].each
      queue_store.enqueue(job: submission_job(id: 'job-1'), now:)
      expiring_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers:,
        lease_duration: 1,
        clock: -> { time_points.next }
      )

      result = expiring_worker.work_once

      expect(result).to be_nil
      expect(stored_job('job-1').state).to eq(:queued)
    end

    it 'fails handlers that accept arbitrary keyword rest arguments' do
      queue_store.enqueue(
        job: submission_job(id: 'job-1', arguments: { account_id: 42 }),
        now:
      )
      keyrest_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers: { 'billing_sync' => ->(**_arguments) {} },
        lease_duration: 30,
        clock: -> { now }
      )

      result = keyrest_worker.work_once

      expect(result.state).to eq(:failed)
      expect(stored_job('job-1').state).to eq(:failed)
    end

    it 'fails handlers that receive unexpected explicit keyword arguments' do
      queue_store.enqueue(
        job: submission_job(id: 'job-1', arguments: { account_id: 42, extra: true }),
        now:
      )
      keyword_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers: { 'billing_sync' => ->(account_id:) { account_id } },
        lease_duration: 30,
        clock: -> { now }
      )

      result = keyword_worker.work_once

      expect(result.state).to eq(:failed)
      expect(stored_job('job-1').state).to eq(:failed)
    end

    it 'treats completion-time reservation loss as a no-op iteration instead of crashing' do
      queue_store.enqueue(job: submission_job(id: 'job-1'), now:)
      store = queue_store
      completed_once = false
      allow(store).to receive(:complete_execution).and_wrap_original do |original, reservation_token:, now:|
        unless completed_once
          completed_once = true
          raise Karya::UnknownReservationError, "reservation #{reservation_token.inspect} was not found"
        end

        original.call(reservation_token:, now:)
      end
      completion_worker = described_class.new(
        queue_store: store,
        worker_id: 'worker-1',
        queues:,
        handlers:,
        lease_duration: 30,
        clock: -> { now }
      )

      result = completion_worker.work_once

      expect(result).to be_nil
    end

    it 'treats failure-time reservation loss as a no-op iteration instead of crashing' do
      queue_store.enqueue(job: submission_job(id: 'job-1'), now:)
      store = queue_store
      failed_once = false
      allow(store).to receive(:fail_execution).and_wrap_original do |original, reservation_token:, now:|
        unless failed_once
          failed_once = true
          raise Karya::UnknownReservationError, "reservation #{reservation_token.inspect} was not found"
        end

        original.call(reservation_token:, now:)
      end
      failure_worker = described_class.new(
        queue_store: store,
        worker_id: 'worker-1',
        queues:,
        handlers: { 'billing_sync' => -> { raise 'boom' } },
        lease_duration: 30,
        clock: -> { now }
      )

      result = failure_worker.work_once

      expect(result).to be_nil
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
      configuration_class = described_class.const_get(:Configuration, false)

      expect do
        configuration_class.from_options(worker_id: 'worker-1')
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

    it 'rejects sleepers that do not respond to call' do
      expect do
        described_class.new(
          queue_store:,
          worker_id: 'worker-1',
          queues:,
          handlers:,
          lease_duration: 30,
          sleeper: Object.new
        )
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /sleeper must respond to #call/)
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

    it 'raises MissingHandlerError when fetching an unknown handler directly' do
      expect do
        described_class.new(
          queue_store:,
          worker_id: 'worker-1',
          queues:,
          handlers:,
          lease_duration: 30
        ).handlers.fetch('missing_handler')
      end.to raise_error(Karya::MissingHandlerError, /missing_handler/)
    end
  end

  describe '#run' do
    it 'stops cleanly when asked to stop on idle' do
      expect(worker.run(stop_when_idle: true)).to be_nil
    end

    it 'does not stop on lease loss when work is requeued' do
      time_points = [
        Time.utc(2026, 3, 29, 12, 0, 0),
        Time.utc(2026, 3, 29, 12, 0, 2),
        Time.utc(2026, 3, 29, 12, 0, 2),
        Time.utc(2026, 3, 29, 12, 0, 2),
        Time.utc(2026, 3, 29, 12, 0, 2),
        Time.utc(2026, 3, 29, 12, 0, 2),
        Time.utc(2026, 3, 29, 12, 0, 2)
      ].each
      queue_store.enqueue(job: submission_job(id: 'job-1'), now:)
      recovering_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers:,
        lease_duration: 1,
        clock: -> { time_points.next },
        sleeper: ->(_duration) {}
      )

      result = recovering_worker.run(stop_when_idle: true)

      expect(result).to be_nil
      expect(stored_job('job-1').state).to eq(:succeeded)
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

    it 'returns the executed job when max_iterations is reached after doing work' do
      queue_store.enqueue(job: submission_job(id: 'job-1'), now:)

      result = worker.run(max_iterations: 1)

      expect(result.state).to eq(:succeeded)
      expect(stored_job('job-1').state).to eq(:succeeded)
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

    it 'sleeps between lease-loss retries' do
      calls = []
      time_points = [
        Time.utc(2026, 3, 29, 12, 0, 0),
        Time.utc(2026, 3, 29, 12, 0, 2),
        Time.utc(2026, 3, 29, 12, 0, 2),
        Time.utc(2026, 3, 29, 12, 0, 4),
        Time.utc(2026, 3, 29, 12, 0, 4),
        Time.utc(2026, 3, 29, 12, 0, 6)
      ].each
      queue_store.enqueue(job: submission_job(id: 'job-1'), now:)
      retrying_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers:,
        lease_duration: 1,
        clock: -> { time_points.next },
        sleeper: ->(duration) { calls << duration }
      )

      retrying_worker.run(poll_interval: 2, max_iterations: 3)

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

  describe 'internal dispatch helpers' do
    it 'filters explicit keyword arguments without symbolizing arbitrary keys' do
      dispatcher = described_class.const_get(:MethodDispatcher, false).new(
        parameters: [%i[req job], %i[keyreq account_id], %i[key mode]]
      )

      normalized = dispatcher.send(:keyword_arguments, { 'account_id' => 42 })

      expect(normalized).to eq(account_id: 42)
    end

    it 'formats the unexpected keyword argument message' do
      dispatcher = described_class.const_get(:MethodDispatcher, false).new(parameters: [%i[keyreq account_id]])

      message = dispatcher.send(:unexpected_arguments_message, ['extra'])

      expect(message).to eq('handler received unexpected argument keys: extra')
    end

    it 'rejects mixed positional and keyword signatures from keyword dispatch' do
      dispatcher = described_class.const_get(:MethodDispatcher, false).new(
        parameters: [%i[req job], %i[keyreq account_id]]
      )

      expect do
        dispatcher.call(arguments: { 'account_id' => 42 }) { |_mode, _payload| nil }
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /handler methods must accept no arguments/)
    end
  end
end
