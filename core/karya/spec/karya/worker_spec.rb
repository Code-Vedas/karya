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
      sleeper:,
      signal_subscriber:
    )
  end

  let(:queue_store) { Karya::QueueStore::InMemory.new(token_generator: -> { 'lease-token' }) }
  let(:queues) { ['billing'] }
  let(:handlers) { { 'billing_sync' => handler } }
  let(:handler) { -> {} }
  let(:now) { Time.utc(2026, 3, 29, 12, 0, 0) }
  let(:sleeper) { ->(_duration) {} }
  let(:signal_subscriber) { nil }

  def submission_job(id:, queue: 'billing', handler_name: 'billing_sync', arguments: {}, created_at: now - 60)
    Karya::Job.new(
      id:,
      queue:,
      handler: handler_name,
      arguments:,
      state: :submission,
      created_at:
    )
  end

  def stored_job(id)
    queue_store.instance_variable_get(:@state).jobs_by_id.fetch(id)
  end

  describe '#work_once' do
    it 'exposes the configured lifecycle registry' do
      lifecycle = Karya::JobLifecycle::Registry.new
      lifecycle_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers:,
        lease_duration: 30,
        lifecycle:
      )

      expect(lifecycle_worker.lifecycle).to be(lifecycle)
    end

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

    it 'passes a mutable copy to positional-hash handlers' do
      received_arguments = nil
      queue_store.enqueue(
        job: submission_job(id: 'job-1', arguments: { metadata: { account_id: 42 }, tags: ['vip'] }),
        now:
      )
      positional_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers: {
          'billing_sync' => lambda do |arguments|
            arguments['metadata']['account_id'] = 99
            arguments['tags'] << 'priority'
            received_arguments = arguments
          end
        },
        lease_duration: 30,
        clock: -> { now }
      )

      result = positional_worker.work_once

      expect(received_arguments).to eq('metadata' => { 'account_id' => 99 }, 'tags' => %w[vip priority])
      expect(stored_job('job-1').arguments).to eq('metadata' => { 'account_id' => 42 }, 'tags' => ['vip'])
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
    it 'accepts an already-normalized handler registry' do
      handler_registry = described_class.const_get(:HandlerRegistry, false).new('billing_sync' => -> {})
      preconfigured_worker = described_class.new(
        queue_store: queue_store,
        worker_id: 'worker-1',
        queues: ['billing'],
        handlers: handler_registry,
        lease_duration: 30
      )

      expect(preconfigured_worker.handlers).to be(handler_registry)
    end

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

    it 'rejects signal subscribers that do not respond to call' do
      expect do
        described_class.new(
          queue_store:,
          worker_id: 'worker-1',
          queues:,
          handlers:,
          lease_duration: 30,
          signal_subscriber: Object.new
        )
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /signal_subscriber must respond to #call/)
    end

    it 'uses default sleeper that calls Kernel.sleep when sleeper is not provided' do
      worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers:,
        lease_duration: 30
      )

      allow(Kernel).to receive(:sleep)
      worker.instance_variable_get(:@runtime).sleep(0.5)
      expect(Kernel).to have_received(:sleep).with(0.5)
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

    it 'stops cleanly when a shutdown signal arrives during idle polling' do
      subscriptions = {}
      shutdown_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers:,
        lease_duration: 30,
        clock: -> { now },
        sleeper: lambda do |_duration|
          subscriptions.fetch('TERM').call
        end,
        signal_subscriber: lambda do |signal, handler|
          subscriptions[signal] = handler
          -> {}
        end
      )

      expect(shutdown_worker.run(poll_interval: 2, max_iterations: 3)).to be_nil
    end

    it 'returns immediately when forced shutdown is requested before the first iteration' do
      forced_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers:,
        lease_duration: 30,
        clock: -> { now },
        signal_subscriber: lambda do |_signal, handler|
          handler.call
          handler.call
          -> {}
        end
      )

      expect(forced_worker.run).to be_nil
    end

    it 'releases a reserved job when shutdown is requested before execution starts' do
      queue_store.enqueue(job: submission_job(id: 'job-1'), now:)
      subscriptions = {}
      time_points = [now, now, now + 1].each
      shutdown_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers:,
        lease_duration: 30,
        clock: -> { time_points.next },
        signal_subscriber: lambda do |signal, handler|
          subscriptions[signal] = handler
          -> {}
        end
      )
      allow(queue_store).to receive(:reserve).and_wrap_original do |original, *args, **kwargs|
        reservation = original.call(*args, **kwargs)
        subscriptions.fetch('TERM').call if reservation
        reservation
      end

      expect(shutdown_worker.run(max_iterations: 1)).to be_nil
      expect(stored_job('job-1').state).to eq(:queued)
    end

    it 'releases a reserved job when shutdown is requested immediately before execution begins' do
      queue_store.enqueue(job: submission_job(id: 'job-1'), now:)
      subscriptions = {}
      shutdown_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers:,
        lease_duration: 30,
        clock: -> { now },
        signal_subscriber: lambda do |signal, handler|
          subscriptions[signal] = handler
          -> {}
        end
      )
      reserve_calls = 0
      allow(queue_store).to receive(:reserve).and_wrap_original do |original, *args, **kwargs|
        reserve_calls += 1
        reservation = original.call(*args, **kwargs)
        subscriptions.fetch('TERM').call if reservation && reserve_calls == 1
        reservation
      end

      expect(shutdown_worker.run(max_iterations: 1)).to be_nil
      expect(stored_job('job-1').state).to eq(:queued)
    end

    it 'treats reservation release loss during shutdown as a no-op iteration' do
      queue_store.enqueue(job: submission_job(id: 'job-1'), now:)
      subscriptions = {}
      shutdown_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers:,
        lease_duration: 30,
        clock: -> { now },
        signal_subscriber: lambda do |signal, handler|
          subscriptions[signal] = handler
          -> {}
        end
      )
      allow(queue_store).to receive(:reserve).and_wrap_original do |original, *args, **kwargs|
        reservation = original.call(*args, **kwargs)
        subscriptions.fetch('TERM').call if reservation
        reservation
      end
      allow(queue_store).to receive(:release).and_raise(Karya::UnknownReservationError, 'missing reservation')

      expect(shutdown_worker.run(max_iterations: 1)).to be_nil
    end

    it 'finishes the running job before exiting when shutdown is requested during execution' do
      queue_store.enqueue(job: submission_job(id: 'job-1'), now:)
      subscriptions = {}
      seen_calls = []
      draining_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers: {
          'billing_sync' => lambda do
            seen_calls << :started
            subscriptions.fetch('INT').call
            seen_calls << :finished
          end
        },
        lease_duration: 30,
        clock: -> { now },
        signal_subscriber: lambda do |signal, handler|
          subscriptions[signal] = handler
          -> {}
        end
      )

      expect(draining_worker.run).to be_nil
      expect(seen_calls).to eq(%i[started finished])
      expect(stored_job('job-1').state).to eq(:succeeded)
    end

    it 'escalates a repeated signal to an immediate stop after the current safe checkpoint' do
      queue_store.enqueue(job: submission_job(id: 'job-1'), now:)
      queue_store.enqueue(job: submission_job(id: 'job-2', created_at: now - 30), now:)
      subscriptions = {}
      releasing_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers: {
          'billing_sync' => lambda do
            subscriptions.fetch('TERM').call
            subscriptions.fetch('INT').call
          end
        },
        lease_duration: 30,
        clock: -> { now },
        signal_subscriber: lambda do |signal, handler|
          subscriptions[signal] = handler
          -> {}
        end
      )

      expect(releasing_worker.run).to be_nil
      expect(stored_job('job-1').state).to eq(:succeeded)
      expect(stored_job('job-2').state).to eq(:queued)
    end

    it 'restores signal subscriptions after run completes' do
      restorers = []
      restoring_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers:,
        lease_duration: 30,
        clock: -> { now },
        signal_subscriber: lambda do |_signal, _handler|
          restorer = instance_spy(Proc)
          restorers << restorer
          -> { restorer.call }
        end
      )

      restoring_worker.run(stop_when_idle: true)

      expect(restorers.length).to eq(2)
      expect(restorers).to all(have_received(:call))
    end

    it 'uses an externally managed shutdown controller without subscribing to process signals' do
      queue_store.enqueue(job: submission_job(id: 'job-1'), now:)
      external_shutdown_controller = instance_double(
        described_class.const_get(:ShutdownController, false),
        force_stop?: false,
        stop_before_reserve?: false,
        stop_after_reserve?: false,
        stop_after_iteration?: false,
        synchronize_pre_execution: nil
      )
      allow(external_shutdown_controller).to receive(:synchronize_pre_execution).and_yield
      externally_managed_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers:,
        lease_duration: 30,
        clock: -> { now },
        signal_subscriber: ->(_signal, _handler) { raise 'should not subscribe' }
      )

      expect(externally_managed_worker.run(stop_when_idle: true, shutdown_controller: external_shutdown_controller)).to be_nil
      expect(stored_job('job-1').state).to eq(:succeeded)
    end

    it 'handles subscription setup failures before shutdown restorers are collected' do
      broken_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers:,
        lease_duration: 30,
        clock: -> { now },
        signal_subscriber: ->(_signal, _handler) { raise 'boom' }
      )

      expect { broken_worker.run(stop_when_idle: true) }.to raise_error(RuntimeError, /boom/)
    end

    it 'restores already-subscribed signals when later subscription setup fails' do
      first_restorer = instance_spy(Proc)
      subscription_count = 0
      broken_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers:,
        lease_duration: 30,
        clock: -> { now },
        signal_subscriber: lambda do |_signal, _handler|
          subscription_count += 1
          raise 'boom' if subscription_count == 2

          -> { first_restorer.call }
        end
      )

      expect { broken_worker.run(stop_when_idle: true) }.to raise_error(RuntimeError, /boom/)
      expect(first_restorer).to have_received(:call)
    end
  end

  describe 'internal dispatch helpers' do
    it 'releases reservations at the second pre-execution shutdown checkpoint' do
      queue_store.enqueue(job: submission_job(id: 'job-1'), now:)
      shutdown_controller = Object.new
      stop_after_reserve_calls = 0
      allow(shutdown_controller).to receive(:stop_before_reserve?).and_return(false)
      allow(shutdown_controller).to receive(:stop_after_reserve?) do
        stop_after_reserve_calls += 1
        stop_after_reserve_calls == 2
      end
      allow(shutdown_controller).to receive(:synchronize_pre_execution).and_yield

      result = worker.send(:work_once_result, shutdown_controller)

      expect(result).to be(described_class.const_get(:NO_WORK_AVAILABLE, false))
      expect(stored_job('job-1').state).to eq(:queued)
    end

    it 'releases the reservation when shutdown becomes visible inside the pre-execution handshake' do
      queue_store.enqueue(job: submission_job(id: 'job-1'), now:)
      shutdown_controller = described_class.const_get(:ShutdownController, false).new
      allow(shutdown_controller).to receive(:synchronize_pre_execution).and_wrap_original do |original, &block|
        shutdown_controller.advance
        original.call(&block)
      end

      result = worker.send(:work_once_result, shutdown_controller)

      expect(result).to be(described_class.const_get(:NO_WORK_AVAILABLE, false))
      expect(stored_job('job-1').state).to eq(:queued)
    end

    it 'returns the no-op restorer when signal_subscriber returns nil' do
      runtime_class = described_class.const_get(:Runtime, false)
      runtime_instance = runtime_class.new(signal_subscriber: ->(_signal, _handler) {})

      expect(runtime_instance.subscribe_signal('TERM', -> {})).to respond_to(:call)
    end

    it 'rejects non-callable signal subscriber restorers' do
      runtime_class = described_class.const_get(:Runtime, false)
      runtime_instance = runtime_class.new(signal_subscriber: ->(_signal, _handler) { 'DEFAULT' })

      expect do
        runtime_instance.subscribe_signal('TERM', -> {})
      end.to raise_error(
        Karya::InvalidWorkerConfigurationError,
        /signal_subscriber must return a callable \(responding to #call\) or nil/
      )
    end

    it 'rejects signal_subscriber set to false' do
      runtime_class = described_class.const_get(:Runtime, false)

      expect do
        runtime_class.new(signal_subscriber: false)
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /signal_subscriber must respond to #call/)
    end

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

    it 'exposes inactive shutdown controller falsey decisions' do
      controller = described_class.const_get(:InactiveShutdownController, false).new

      expect(controller.force_stop?).to be(false)
      expect(controller.stop_polling?).to be(false)
      expect(controller.stop_before_reserve?).to be(false)
      expect(controller.stop_after_reserve?).to be(false)
      expect(controller.stop_after_iteration?).to be(false)
    end

    it 'keeps force-stop as a terminal shutdown state' do
      controller = described_class.const_get(:ShutdownController, false).new

      controller.advance
      controller.advance
      controller.advance

      expect(controller.force_stop?).to be(true)
      expect(controller.stop_polling?).to be(true)
    end

    it 'emits instrumentation events for a successful execution' do
      instrumented_events = []
      queue_store.enqueue(job: submission_job(id: 'job-1'), now:)
      runtime_class = described_class.const_get(:Runtime, false)
      runtime_instance = runtime_class.new(
        clock: -> { now },
        sleeper:,
        instrumenter: ->(event, payload) { instrumented_events << [event, payload] }
      )
      instrumented_worker = described_class.new(
        queue_store:,
        worker_id: 'worker-1',
        queues:,
        handlers:,
        lease_duration: 30,
        runtime: runtime_instance
      )

      instrumented_worker.work_once

      expect(instrumented_events.map(&:first)).to include(
        'worker.job.reserved',
        'worker.job.started',
        'worker.job.succeeded'
      )
      expect(instrumented_events.last.last).to include(worker_id: 'worker-1')
    end

    it 'swallows instrumentation failures and logs them' do
      logger = instance_double(Karya::Internal::NullLogger, error: nil)
      runtime_class = described_class.const_get(:Runtime, false)
      runtime_instance = runtime_class.new(
        instrumenter: ->(_event, _payload) { raise 'boom' },
        logger:
      )

      expect(runtime_instance.instrument('worker.poll', worker_id: 'worker-1')).to be_nil
      expect(logger).to have_received(:error).with(
        'instrumentation failed',
        event: 'worker.poll',
        error_class: 'RuntimeError',
        error_message: 'boom'
      )
    end
  end
end
