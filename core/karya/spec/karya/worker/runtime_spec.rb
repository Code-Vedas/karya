# frozen_string_literal: true

RSpec.describe 'Karya::Worker::Runtime' do
  let(:runtime_class) { Karya::Worker.const_get(:Runtime, false) }
  let(:logger) do
    double(debug: nil, info: nil, warn: nil, error: nil)
  end

  it 'extracts known runtime options from a mutable options hash' do
    sleeper = ->(_duration) {}
    options = { sleeper: sleeper, extra: true }

    runtime = runtime_class.from_options(options)

    expect(runtime.sleep(1)).to be_nil
    expect(options).to eq({ extra: true })
  end

  it 'returns a noop subscription when no signal subscriber is configured' do
    runtime = runtime_class.new(logger: logger)

    expect(runtime.subscribe_signal('TERM', -> {})).to respond_to(:call)
  end

  it 'logs and swallows instrumentation failures' do
    instrumenter = ->(_event, _payload) { raise 'boom' }
    runtime = runtime_class.new(logger: logger, instrumenter: instrumenter)

    expect(runtime.instrument('worker.poll', {})).to be_nil
    expect(logger).to have_received(:error).with('instrumentation failed', hash_including(error_message: 'boom'))
  end

  it 'skips hook payload snapshots when no hooks are configured' do
    allow(Karya::Internal::ImmutableHookPayload).to receive(:snapshot).and_call_original
    allow(Karya::Internal::ImmutableHookPayload).to receive(:snapshot_pair).and_call_original
    allow(Karya::Internal::PayloadInput).to receive(:new).and_call_original
    runtime = runtime_class.new(logger: logger, instrumenter: nil, outbound_event_dispatcher: nil)

    expect(runtime.instrument('worker.poll', { worker_id: 'worker-1' })).to be_nil
    expect(Karya::Internal::PayloadInput).not_to have_received(:new)
    expect(Karya::Internal::ImmutableHookPayload).not_to have_received(:snapshot)
    expect(Karya::Internal::ImmutableHookPayload).not_to have_received(:snapshot_pair)
  end

  it 'builds one hook payload snapshot when only one hook is configured' do
    instrumenter_payload = nil
    allow(Karya::Internal::ImmutableHookPayload).to receive(:snapshot).and_call_original
    allow(Karya::Internal::ImmutableHookPayload).to receive(:snapshot_pair).and_call_original
    runtime = runtime_class.new(
      logger: logger,
      instrumenter: ->(_event, payload) { instrumenter_payload = payload },
      outbound_event_dispatcher: nil
    )

    expect(runtime.instrument('worker.poll', { worker_id: 'worker-1' })).to be_nil
    expect(Karya::Internal::ImmutableHookPayload).to have_received(:snapshot).once
    expect(Karya::Internal::ImmutableHookPayload).not_to have_received(:snapshot_pair)
    expect(instrumenter_payload).to eq(worker_id: 'worker-1')
    expect(instrumenter_payload).to be_frozen
  end

  it 'dispatches supported outbound events through the configured dispatcher' do
    deliveries = []
    dispatcher = Karya::OutboundEvents::Dispatcher.new(
      delivery_handler: ->(delivery) { deliveries << delivery },
      signer: Karya::OutboundEvents::WebhookSigner.new(secret: 'secret'),
      clock: -> { Time.utc(2026, 4, 29, 12, 0, 0) },
      event_id_generator: -> { 'event-1' }
    )
    runtime = runtime_class.new(logger: logger, outbound_event_dispatcher: dispatcher)

    runtime.instrument(
      'worker.job.started',
      {
        reservation_token: 'lease-1',
        job_id: 'job-1',
        handler: 'billing_sync',
        queue: 'billing',
        worker_id: 'worker-1'
      }
    )

    expect(deliveries.length).to eq(1)
    expect(deliveries.first.event.type).to eq('io.karya.worker.job.started')
  end

  it 'rejects invalid outbound event dispatchers during initialization' do
    expect do
      runtime_class.new(logger: logger, outbound_event_dispatcher: Object.new)
    end.to raise_error(Karya::InvalidWorkerConfigurationError, /outbound_event_dispatcher must respond to #call/)
  end

  it 'still dispatches outbound events when the instrumenter raises' do
    deliveries = []
    dispatcher = Karya::OutboundEvents::Dispatcher.new(
      delivery_handler: ->(delivery) { deliveries << delivery },
      clock: -> { Time.utc(2026, 4, 29, 12, 0, 0) },
      event_id_generator: -> { 'event-1' }
    )
    runtime = runtime_class.new(
      logger: logger,
      instrumenter: ->(_event, _payload) { raise 'boom' },
      outbound_event_dispatcher: dispatcher
    )

    expect(runtime.instrument(
             'worker.job.started',
             {
               reservation_token: 'lease-1',
               job_id: 'job-1',
               handler: 'billing_sync',
               queue: 'billing',
               worker_id: 'worker-1'
             }
           )).to be_nil

    expect(deliveries.length).to eq(1)
    expect(logger).to have_received(:error).with('instrumentation failed', hash_including(error_message: 'boom'))
  end

  it 'isolates instrumentation and outbound dispatch payload snapshots' do
    instrumentation_payload = nil
    outbound_payload = nil
    mutation_error = nil
    job_id = +'job-1'
    stage = +'original'
    stage.freeze
    runtime = runtime_class.new(
      logger: logger,
      instrumenter: lambda do |_event, payload|
        instrumentation_payload = payload
        mutation_error = begin
          payload.fetch(:metadata)['stage'] = 'mutated'
          nil
        rescue StandardError => e
          e
        end
      end,
      outbound_event_dispatcher: ->(_event, payload) { outbound_payload = payload }
    )

    runtime.instrument('worker.job.started', { job_id:, metadata: { 'stage' => stage } })

    expect(mutation_error).to be_a(FrozenError)
    expect(instrumentation_payload).not_to be(outbound_payload)
    expect(instrumentation_payload).to eq(outbound_payload)
    expect(outbound_payload).to eq(job_id: 'job-1', metadata: { 'stage' => 'original' })
    expect(outbound_payload).to be_frozen
    expect(instrumentation_payload.fetch(:job_id)).not_to be(job_id)
    expect(outbound_payload.fetch(:job_id)).not_to be(job_id)
    expect(outbound_payload.fetch(:job_id)).to be_frozen
    expect(outbound_payload.fetch(:metadata)).to be_frozen
    expect(instrumentation_payload.fetch(:metadata).fetch('stage')).to be(stage)
    expect(outbound_payload.fetch(:metadata).fetch('stage')).to be(stage)
  end

  it 'logs and swallows outbound event dispatch failures' do
    runtime = runtime_class.new(
      logger: logger,
      outbound_event_dispatcher: ->(_event, _payload) { raise 'boom' }
    )

    expect(runtime.instrument('worker.job.started', { worker_id: 'worker-1' })).to be_nil
    expect(logger).to have_received(:error).with('outbound event dispatch failed', hash_including(error_message: 'boom'))
  end

  it 'rejects unsupported mutable payload values before dispatching hooks' do
    runtime = runtime_class.new(
      logger: logger,
      instrumenter: ->(_event, _payload) {}
    )

    expect do
      runtime.instrument('worker.job.started', { worker_id: 'worker-1', metadata: Object.new })
    end.to raise_error(
      Karya::InvalidWorkerConfigurationError,
      'payload values must be nil, booleans, numerics, strings, symbols, times, arrays, or hashes'
    )
  end

  it 'ignores unsupported outbound events without logging dispatch failures' do
    runtime = runtime_class.new(
      logger: logger,
      outbound_event_dispatcher: Karya::OutboundEvents::Dispatcher.new(
        delivery_handler: ->(_delivery) {},
        clock: -> { Time.utc(2026, 4, 29, 12, 0, 0) },
        event_id_generator: -> { 'event-1' }
      )
    )

    expect(runtime.instrument('worker.poll', { worker_id: 'worker-1' })).to be_nil
    expect(logger).not_to have_received(:error).with('outbound event dispatch failed', anything)
  end

  it 'uses one snapshot when only the instrumenter should run for unsupported built-in outbound events' do
    instrumenter_payload = nil
    allow(Karya::Internal::ImmutableHookPayload).to receive(:snapshot).and_call_original
    allow(Karya::Internal::ImmutableHookPayload).to receive(:snapshot_pair).and_call_original
    runtime = runtime_class.new(
      logger: logger,
      instrumenter: ->(_event, payload) { instrumenter_payload = payload },
      outbound_event_dispatcher: Karya::OutboundEvents::Dispatcher.new(
        delivery_handler: ->(_delivery) { raise 'should not dispatch unsupported events' }
      )
    )

    expect(runtime.instrument('worker.poll', { worker_id: 'worker-1' })).to be_nil
    expect(Karya::Internal::ImmutableHookPayload).to have_received(:snapshot).once
    expect(Karya::Internal::ImmutableHookPayload).not_to have_received(:snapshot_pair)
    expect(instrumenter_payload).to eq(worker_id: 'worker-1')
  end

  it 'returns early from private emit helpers when the corresponding hook is absent' do
    runtime = runtime_class.new(logger: logger, instrumenter: nil, outbound_event_dispatcher: nil)

    expect(runtime.send(:emit_instrumentation, 'worker.poll', { worker_id: 'worker-1' })).to be_nil
    expect(runtime.send(:emit_outbound_event, 'worker.poll', { worker_id: 'worker-1' })).to be_nil
  end

  it 'swallows unsupported outbound event errors from custom dispatchers' do
    runtime = runtime_class.new(
      logger: logger,
      outbound_event_dispatcher: ->(_event, _payload) { raise Karya::UnsupportedOutboundEventError, 'skip' }
    )

    expect(runtime.instrument('worker.job.started', { worker_id: 'worker-1' })).to be_nil
    expect(logger).not_to have_received(:error).with('outbound event dispatch failed', anything)
  end
end
