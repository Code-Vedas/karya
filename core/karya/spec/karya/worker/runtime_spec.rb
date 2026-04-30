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
      reservation_token: 'lease-1',
      job_id: 'job-1',
      handler: 'billing_sync',
      queue: 'billing',
      worker_id: 'worker-1'
    )

    expect(deliveries.length).to eq(1)
    expect(deliveries.first.event.type).to eq('io.karya.worker.job.started')
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
             reservation_token: 'lease-1',
             job_id: 'job-1',
             handler: 'billing_sync',
             queue: 'billing',
             worker_id: 'worker-1'
           )).to be_nil

    expect(deliveries.length).to eq(1)
    expect(logger).to have_received(:error).with('instrumentation failed', hash_including(error_message: 'boom'))
  end

  it 'logs and swallows outbound event dispatch failures' do
    runtime = runtime_class.new(
      logger: logger,
      outbound_event_dispatcher: ->(_event, _payload) { raise 'boom' }
    )

    expect(runtime.instrument('worker.job.started', worker_id: 'worker-1')).to be_nil
    expect(logger).to have_received(:error).with('outbound event dispatch failed', hash_including(error_message: 'boom'))
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

    expect(runtime.instrument('worker.poll', worker_id: 'worker-1')).to be_nil
    expect(logger).not_to have_received(:error).with('outbound event dispatch failed', anything)
  end

  it 'swallows unsupported outbound event errors from custom dispatchers' do
    runtime = runtime_class.new(
      logger: logger,
      outbound_event_dispatcher: ->(_event, _payload) { raise Karya::UnsupportedOutboundEventError, 'skip' }
    )

    expect(runtime.instrument('worker.job.started', worker_id: 'worker-1')).to be_nil
    expect(logger).not_to have_received(:error).with('outbound event dispatch failed', anything)
  end
end
