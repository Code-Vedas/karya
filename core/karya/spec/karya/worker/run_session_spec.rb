# frozen_string_literal: true

RSpec.describe 'Karya::Worker::RunSession' do
  let(:run_session_class) { Karya::Worker.const_get(:RunSession, false) }
  let(:shutdown_controller_class) { Karya::Worker.const_get(:ShutdownController, false) }
  let(:runtime_class) { Karya::Worker.const_get(:Runtime, false) }
  let(:worker) { instance_double(Karya::Worker) }
  let(:iteration_limit) { instance_double(Karya::Internal::RuntimeSupport::IterationLimit, normalize: 5) }
  let(:shutdown_controller) do
    instance_double(
      shutdown_controller_class,
      force_stop?: force_stop,
      stop_after_iteration?: false
    )
  end
  let(:runtime) { instance_double(runtime_class, sleep: nil) }
  let(:result) { Karya::Worker.const_get(:NO_WORK_AVAILABLE, false) }
  let(:force_stop) { false }

  before do
    allow(worker).to receive(:queues).and_return(['billing'])
    allow(worker).to receive(:send) do |message, *_args|
      case message
      when :runtime
        runtime
      when :work_once_result
        result
      end
    end
  end

  it 'returns nil when the loop stops on idle' do
    allow(iteration_limit).to receive(:reached?).with(1).and_return(false)

    session = run_session_class.new(
      worker: worker,
      iteration_limit: iteration_limit,
      normalized_poll_interval: 1,
      shutdown_controller: shutdown_controller,
      stop_when_idle: true
    )

    expect(session.call).to be_nil
  end

  it 'sleeps after idle iterations when continuing to poll' do
    allow(iteration_limit).to receive(:reached?).with(1).and_return(false)

    session = run_session_class.new(
      worker: worker,
      iteration_limit: iteration_limit,
      normalized_poll_interval: 1,
      shutdown_controller: shutdown_controller,
      stop_when_idle: false
    )

    allow(shutdown_controller).to receive(:force_stop?).and_return(false, true)
    allow(worker).to receive(:send).with(:report_runtime_state, 'stopping')

    session.call

    expect(runtime).to have_received(:sleep).with(1)
  end
end
