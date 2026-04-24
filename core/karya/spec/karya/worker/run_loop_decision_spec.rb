# frozen_string_literal: true

RSpec.describe 'Karya::Worker::RunLoopDecision' do
  let(:run_loop_decision_class) { Karya::Worker.const_get(:RunLoopDecision, false) }
  let(:shutdown_controller_class) { Karya::Worker.const_get(:ShutdownController, false) }
  let(:continue_running) { Karya::Worker.const_get(:CONTINUE_RUNNING, false) }
  let(:iteration_limit) { instance_double(Karya::Internal::RuntimeSupport::IterationLimit, reached?: reached) }
  let(:shutdown_controller) { instance_double(shutdown_controller_class, stop_after_iteration?: stop_after_iteration) }
  let(:state) do
    {
      idle: idle,
      iteration_limit: iteration_limit,
      iterations: 3,
      lease_lost: lease_lost,
      shutdown_controller: shutdown_controller,
      stop_when_idle: stop_when_idle
    }
  end
  let(:result) { instance_double(Karya::Job) }
  let(:idle) { false }
  let(:lease_lost) { false }
  let(:reached) { false }
  let(:stop_after_iteration) { false }
  let(:stop_when_idle) { false }

  it 'continues running when iteration limits are not reached' do
    expect(run_loop_decision_class.new(result:, state:).resolve).to equal(continue_running)
  end

  it 'returns nil when shutdown should stop after the iteration' do
    stopping_controller = instance_double(shutdown_controller_class, stop_after_iteration?: true)

    expect(run_loop_decision_class.new(result:, state: state.merge(shutdown_controller: stopping_controller)).resolve).to be_nil
  end

  it 'returns nil when stopping while idle' do
    expect(run_loop_decision_class.new(result:, state: state.merge(idle: true, stop_when_idle: true)).resolve).to be_nil
  end

  it 'returns the result when a non-idle bounded run reaches its iteration limit' do
    bounded_limit = instance_double(Karya::Internal::RuntimeSupport::IterationLimit, reached?: true)

    expect(run_loop_decision_class.new(result:, state: state.merge(iteration_limit: bounded_limit)).resolve).to eq(result)
  end
end
