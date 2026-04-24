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
end
