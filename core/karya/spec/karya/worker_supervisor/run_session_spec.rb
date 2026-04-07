# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::WorkerSupervisor::RunSession' do
  let(:described_class) { Karya::WorkerSupervisor.const_get(:RunSession, false) }
  let(:runtime_state_store_class) { Karya::WorkerSupervisor.const_get(:RuntimeStateStore, false) }
  let(:shutdown_controller_class) { Karya::WorkerSupervisor.const_get(:ShutdownController, false) }
  let(:wakeup_signal_class) { Karya::WorkerSupervisor.const_get(:WakeupSignal, false) }
  let(:supervisor) { instance_double(Karya::WorkerSupervisor) }
  let(:shutdown_controller) { instance_double(shutdown_controller_class, begin_drain: true, force_stop!: true, force_stop?: false) }
  let(:runtime_state_store) { instance_double(runtime_state_store_class, mark_supervisor_phase: nil) }

  it 'returns immediately when process_wait_result resolves to a final status' do
    session = described_class.new(supervisor:, shutdown_controller:)
    allow(supervisor).to receive(:desired_child_count).and_return(1)
    allow(supervisor).to receive(:spawn_missing_children)
    allow(session).to receive(:update_signal_state)
    allow(session).to receive_messages(child_pids: { 100 => true }, process_wait_result: 7)

    expect(session.call).to eq(7)
  end

  it 'does not advance shutdown state when drain was already requested' do
    allow(shutdown_controller).to receive(:begin_drain).and_return(false)
    allow(supervisor).to receive(:runtime_state_store).and_return(runtime_state_store)

    described_class.new(supervisor:, shutdown_controller:).request_drain

    expect(runtime_state_store).not_to have_received(:mark_supervisor_phase)
  end

  it 'interrupts the supervisor wait loop when drain is requested' do
    allow(supervisor).to receive(:runtime_state_store).and_return(runtime_state_store)
    allow(wakeup_signal_class).to receive(:interrupt)

    described_class.new(supervisor:, shutdown_controller:).request_drain

    expect(wakeup_signal_class).to have_received(:interrupt).with('USR1')
  end

  it 'still wakes the supervisor wait loop when drain persistence fails after the state transition' do
    allow(supervisor).to receive(:runtime_state_store).and_return(runtime_state_store)
    allow(runtime_state_store).to receive(:mark_supervisor_phase).and_raise(
      Karya::WorkerSupervisor::InvalidRuntimeStateFileError,
      'timed out acquiring runtime state lock'
    )
    allow(wakeup_signal_class).to receive(:interrupt)
    allow(shutdown_controller).to receive(:draining?).and_return(true)

    expect do
      described_class.new(supervisor:, shutdown_controller:).request_drain
    end.to raise_error(Karya::WorkerSupervisor::InvalidRuntimeStateFileError, /timed out acquiring runtime state lock/)
    expect(wakeup_signal_class).to have_received(:interrupt).with('USR1')
  end

  it 'interrupts the supervisor wait loop when force-stop is requested' do
    allow(supervisor).to receive(:runtime_state_store).and_return(runtime_state_store)
    allow(wakeup_signal_class).to receive(:interrupt)

    described_class.new(supervisor:, shutdown_controller:).request_force_stop

    expect(wakeup_signal_class).to have_received(:interrupt).with('USR1')
  end

  it 'still wakes the supervisor wait loop when force-stop persistence fails after the state transition' do
    allow(supervisor).to receive(:runtime_state_store).and_return(runtime_state_store)
    allow(runtime_state_store).to receive(:mark_supervisor_phase).and_raise(
      Karya::WorkerSupervisor::InvalidRuntimeStateFileError,
      'timed out acquiring runtime state lock'
    )
    allow(wakeup_signal_class).to receive(:interrupt)
    allow(shutdown_controller).to receive(:force_stop?).and_return(true)

    expect do
      described_class.new(supervisor:, shutdown_controller:).request_force_stop
    end.to raise_error(Karya::WorkerSupervisor::InvalidRuntimeStateFileError, /timed out acquiring runtime state lock/)
    expect(wakeup_signal_class).to have_received(:interrupt).with('USR1')
  end

  it 'does not rewrite the phase or interrupt the loop when force-stop was already requested' do
    allow(shutdown_controller).to receive(:force_stop!).and_return(false)
    allow(supervisor).to receive(:runtime_state_store).and_return(runtime_state_store)
    allow(wakeup_signal_class).to receive(:interrupt)

    described_class.new(supervisor:, shutdown_controller:).request_force_stop

    expect(runtime_state_store).not_to have_received(:mark_supervisor_phase)
    expect(wakeup_signal_class).not_to have_received(:interrupt)
  end

  it 'does not overwrite drain with force-stop behavior when drain loses the race to an external escalation' do
    allow(shutdown_controller).to receive(:begin_drain).and_return(false)
    allow(supervisor).to receive(:runtime_state_store).and_return(runtime_state_store)
    allow(wakeup_signal_class).to receive(:interrupt)

    described_class.new(supervisor:, shutdown_controller:).request_drain

    expect(runtime_state_store).not_to have_received(:mark_supervisor_phase)
    expect(wakeup_signal_class).not_to have_received(:interrupt)
  end
end
