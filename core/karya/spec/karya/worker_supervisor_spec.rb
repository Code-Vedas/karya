# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'tmpdir'
require 'fileutils'

RSpec.describe Karya::WorkerSupervisor do
  subject(:supervisor) do
    described_class.new(
      queue_store: queue_store,
      worker_id: 'worker-supervisor',
      queues: ['billing'],
      handlers: { 'billing_sync' => -> {} },
      lease_duration: 30,
      processes: processes,
      threads: threads,
      poll_interval: 0,
      max_iterations: max_iterations,
      stop_when_idle: stop_when_idle,
      runtime: runtime,
      child_worker_class: child_worker_class
    )
  end

  let(:queue_store) { instance_double(Karya::QueueStore) }
  let(:child_worker_class) { class_double(Karya::Worker) }
  let(:processes) { 1 }
  let(:threads) { 1 }
  let(:max_iterations) { 1 }
  let(:stop_when_idle) { false }
  let(:subscriptions) { {} }
  let(:forked_pids) { [] }
  let(:poll_wait_results) { [] }
  let(:wait_results) { [] }
  let(:killed_processes) { [] }
  let(:signal_subscriber) do
    lambda do |signal, handler|
      subscriptions[signal] = handler
      -> {}
    end
  end
  let(:runtime) do
    instance_double(
      described_class.const_get(:Runtime, false),
      signal_subscriber: nil,
      subscribe_signal: nil,
      fork_child: nil,
      instrument: nil,
      process_alive?: true,
      poll_for_child_exit: nil,
      wait_for_child: nil,
      kill_process: nil
    )
  end
  let(:success_status) { instance_double(Process::Status, success?: true) }
  let(:failure_status) { instance_double(Process::Status, success?: false) }

  before do
    allow(runtime).to receive(:subscribe_signal) do |signal, handler|
      signal_subscriber.call(signal, handler)
    end
    allow(runtime).to receive(:fork_child) do |&block|
      pid = 100 + forked_pids.length
      forked_pids << pid
      block.call if execute_child_block?
      pid
    end
    allow(runtime).to receive(:wait_for_child) do
      wait_results.shift
    end
    allow(runtime).to receive(:poll_for_child_exit) do
      poll_wait_results.shift
    end
    allow(runtime).to receive(:process_alive?).and_return(true)
    allow(runtime).to receive(:kill_process) do |signal, pid|
      killed_processes << [signal, pid]
    end
    allow(child_worker_class).to receive(:new).and_return(instance_double(Karya::Worker, run: nil))
  end

  def execute_child_block?
    false
  end

  describe '#run' do
    it 'starts the configured number of child workers' do
      wait_results.push([100, success_status], [101, success_status])
      allow(child_worker_class).to receive(:new)
      process_count = 2

      described_class.new(
        queue_store: queue_store,
        worker_id: 'worker-supervisor',
        queues: ['billing'],
        handlers: { 'billing_sync' => -> {} },
        lease_duration: 30,
        processes: process_count,
        threads: 1,
        poll_interval: 0,
        max_iterations: 1,
        runtime: runtime,
        child_worker_class: child_worker_class
      ).run

      expect(forked_pids).to eq([100, 101])
    end

    it 'replaces unexpectedly exited children in unbounded mode' do
      wait_call_count = 0
      allow(runtime).to receive(:wait_for_child) do
        wait_call_count += 1
        subscriptions.fetch('TERM').call if wait_call_count == 3
        wait_results.shift
      end
      wait_results.push([100, failure_status], [101, success_status], nil, [102, success_status])

      unbounded_supervisor = described_class.new(
        queue_store: queue_store,
        worker_id: 'worker-supervisor',
        queues: ['billing'],
        handlers: { 'billing_sync' => -> {} },
        lease_duration: 30,
        processes: 1,
        threads: 1,
        poll_interval: 0,
        stop_when_idle: false,
        runtime: runtime,
        child_worker_class: child_worker_class
      )

      expect(unbounded_supervisor.run).to eq(0)
      expect(forked_pids).to eq([100, 101, 102])
    end

    it 'counts failed child exits toward completion in bounded mode and returns non-zero' do
      wait_results << [100, failure_status]

      expect(supervisor.run).to eq(1)
      expect(forked_pids).to eq([100])
    end

    it 'does not replace children once drain begins' do
      wait_call_count = 0
      allow(runtime).to receive(:wait_for_child) do
        wait_call_count += 1
        subscriptions.fetch('TERM').call if wait_call_count == 1
        wait_results.shift
      end
      wait_results.push(nil, [100, success_status])

      expect(supervisor.run).to eq(0)
      expect(forked_pids).to eq([100])
      expect(killed_processes).to eq([['TERM', 100]])
    end

    it 'stops spawning additional children once shutdown begins during the spawn loop' do
      allow(runtime).to receive(:fork_child) do
        pid = 100 + forked_pids.length
        forked_pids << pid
        subscriptions.fetch('TERM').call if pid == 100
        pid
      end
      wait_results << [100, success_status]

      draining_supervisor = described_class.new(
        queue_store: queue_store,
        worker_id: 'worker-supervisor',
        queues: ['billing'],
        handlers: { 'billing_sync' => -> {} },
        lease_duration: 30,
        processes: 2,
        threads: 1,
        poll_interval: 0,
        max_iterations: 2,
        runtime: runtime,
        child_worker_class: child_worker_class
      )

      expect(draining_supervisor.run).to eq(0)
      expect(forked_pids).to eq([100])
      expect(killed_processes).to eq([['TERM', 100]])
    end

    it 'ignores exited pids that are not tracked children' do
      wait_results.push([999, success_status], [100, success_status])

      expect(supervisor.run).to eq(0)
      expect(forked_pids).to eq([100])
    end

    it 'prunes stale tracked children when wait_for_child returns nil' do
      wait_results << nil
      allow(runtime).to receive(:process_alive?).with(100).and_return(false)

      expect(supervisor.run).to eq(1)
      expect(forked_pids).to eq([100])
    end

    it 'uses the configured process count for unbounded runs until drain begins' do
      wait_call_count = 0
      allow(runtime).to receive(:wait_for_child) do
        wait_call_count += 1
        if wait_call_count == 1
          subscriptions.fetch('TERM').call
          nil
        else
          wait_results.shift
        end
      end
      wait_results.push([100, success_status])

      unbounded_supervisor = described_class.new(
        queue_store: queue_store,
        worker_id: 'worker-supervisor',
        queues: ['billing'],
        handlers: { 'billing_sync' => -> {} },
        lease_duration: 30,
        processes: 1,
        threads: 1,
        poll_interval: 0,
        stop_when_idle: false,
        runtime: runtime,
        child_worker_class: child_worker_class
      )

      expect(unbounded_supervisor.run).to eq(0)
      expect(forked_pids).to eq([100])
      expect(killed_processes).to eq([['TERM', 100]])
    end

    it 'escalates repeated shutdown signals to forced termination' do
      wait_call_count = 0
      allow(runtime).to receive(:wait_for_child) do
        wait_call_count += 1
        case wait_call_count
        when 1
          subscriptions.fetch('TERM').call
          nil
        when 2
          subscriptions.fetch('INT').call
          nil
        else
          [100, failure_status]
        end
      end

      expect(supervisor.run).to eq(1)
      expect(killed_processes).to eq([['TERM', 100], ['KILL', 100]])
    end

    it 'supports begin_drain through the public control API while running' do
      wait_call_count = 0
      allow(runtime).to receive(:wait_for_child) do
        wait_call_count += 1
        if wait_call_count == 1
          supervisor.begin_drain
          nil
        else
          wait_results.shift
        end
      end
      wait_results << [100, success_status]

      expect(supervisor.run).to eq(0)
      expect(killed_processes).to eq([['TERM', 100]])
      expect(supervisor.runtime_snapshot.phase).to eq('stopped')
    end

    it 'supports begin_drain through the public control API without reading the runtime state file' do
      wait_call_count = 0
      supervisor_with_runtime_state = nil
      runtime_state_store = instance_double(
        described_class.const_get(:RuntimeStateStore, false),
        write_running: nil,
        write_stopped: nil,
        control_socket_path: '/tmp/runtime.sock',
        instance_token: 'runtime-token',
        snapshot: nil,
        register_child: nil,
        mark_supervisor_phase: nil,
        mark_child_phase: nil,
        mark_child_stopped: nil
      )
      allow(runtime_state_store).to receive(:snapshot).and_raise('should not read snapshot for in-process control')
      allow(runtime).to receive(:wait_for_child) do
        wait_call_count += 1
        if wait_call_count == 1
          supervisor_with_runtime_state.begin_drain
          nil
        else
          wait_results.shift
        end
      end
      wait_results << [100, success_status]
      supervisor_with_runtime_state = described_class.new(
        queue_store: queue_store,
        worker_id: 'worker-supervisor',
        queues: ['billing'],
        handlers: { 'billing_sync' => -> {} },
        lease_duration: 30,
        processes: 1,
        threads: 1,
        poll_interval: 0,
        max_iterations: 1,
        runtime: runtime,
        runtime_state_store: runtime_state_store,
        child_worker_class: child_worker_class
      )

      expect(supervisor_with_runtime_state.run).to eq(0)
      expect(killed_processes).to eq([['TERM', 100]])
      expect(runtime_state_store).not_to have_received(:snapshot)
    end

    it 'supports force_stop through the public control API while running' do
      wait_call_count = 0
      allow(runtime).to receive(:wait_for_child) do
        wait_call_count += 1
        if wait_call_count == 1
          supervisor.force_stop
          nil
        else
          wait_results.shift
        end
      end
      wait_results << [100, failure_status]

      expect(supervisor.run).to eq(1)
      expect(killed_processes).to eq([['KILL', 100]])
      expect(supervisor.runtime_snapshot.phase).to eq('stopped')
    end

    it 'passes child worker options through to Karya::Worker' do
      wait_results << [100, success_status]
      worker_instance = instance_double(Karya::Worker, run: nil)
      allow(child_worker_class).to receive(:new).and_return(worker_instance)
      allow(runtime).to receive(:signal_subscriber).and_return(signal_subscriber)
      allow(runtime).to receive(:fork_child) do |&block|
        pid = 100 + forked_pids.length
        forked_pids << pid
        block.call
        pid
      end

      expect(supervisor.run).to eq(0)
      expect(child_worker_class).to have_received(:new).with(
        queue_store: queue_store,
        worker_id: match(/worker-supervisor:\d+:thread-1/),
        queues: ['billing'],
        handlers: satisfy { |value| value.respond_to?(:fetch) },
        lease_duration: 30,
        lifecycle: Karya::JobLifecycle.default_registry,
        state_reporter: respond_to(:call)
      )
      expect(worker_instance).to have_received(:run).with(
        poll_interval: 0,
        max_iterations: 1,
        stop_when_idle: false,
        shutdown_controller: instance_of(described_class.const_get(:ShutdownController, false))
      )
    end

    it 'starts the configured number of worker threads in each child process' do
      wait_results << [100, success_status]
      worker_instances = []
      allow(child_worker_class).to receive(:new) do |**kwargs|
        worker_instances << kwargs.fetch(:worker_id)
        instance_double(Karya::Worker, run: nil)
      end
      allow(runtime).to receive(:fork_child) do |&block|
        forked_pids << 100
        block.call
        100
      end

      threaded_supervisor = described_class.new(
        queue_store: queue_store,
        worker_id: 'worker-supervisor',
        queues: ['billing'],
        handlers: { 'billing_sync' => -> {} },
        lease_duration: 30,
        processes: 1,
        threads: 2,
        poll_interval: 0,
        max_iterations: 1,
        runtime: runtime,
        child_worker_class: child_worker_class
      )

      expect(threaded_supervisor.run).to eq(0)
      expect(worker_instances.sort).to match(
        [
          a_string_matching(/worker-supervisor:\d+:thread-1/),
          a_string_matching(/worker-supervisor:\d+:thread-2/)
        ]
      )
    end

    it 'writes a runtime state file with supervisor and child topology' do
      state_dir = Dir.mktmpdir('karya-runtime-state')
      state_file = File.join(state_dir, 'runtime.json')
      worker_instance = instance_double(Karya::Worker, run: nil)
      allow(child_worker_class).to receive(:new) do |**kwargs|
        kwargs.fetch(:state_reporter).call(worker_id: kwargs.fetch(:worker_id), state: 'polling')
        worker_instance
      end
      allow(runtime).to receive(:signal_subscriber).and_return(signal_subscriber)
      allow(runtime).to receive(:fork_child) do |&block|
        pid = 100 + forked_pids.length
        forked_pids << pid
        block.call
        pid
      end
      wait_results << [100, success_status]

      described_class.new(
        queue_store: queue_store,
        worker_id: 'worker-supervisor',
        queues: ['billing'],
        handlers: { 'billing_sync' => -> {} },
        lease_duration: 30,
        processes: 1,
        threads: 1,
        poll_interval: 0,
        max_iterations: 1,
        runtime: runtime,
        state_file:,
        child_worker_class: child_worker_class
      ).run

      snapshot = described_class::RuntimeStateStore.read_snapshot!(state_file)
      expect(snapshot.worker_id).to eq('worker-supervisor')
      expect(snapshot.phase).to eq('stopped')
      expect(snapshot.child_processes.map(&:pid)).to include(100)
      expect(snapshot.child_processes.flat_map(&:threads).map(&:worker_id)).to include(a_string_matching(/worker-supervisor:\d+:thread-1/))
    ensure
      FileUtils.rm_rf(state_dir) if state_dir && Dir.exist?(state_dir)
    end

    it 'resets inherited INT and TERM traps before running a child worker' do
      wait_results << [100, success_status]
      worker_instance = instance_double(Karya::Worker, run: nil)
      allow(child_worker_class).to receive(:new).and_return(worker_instance)
      allow(runtime).to receive(:fork_child) do |&block|
        pid = 100 + forked_pids.length
        forked_pids << pid
        block.call
        pid
      end
      allow(Signal).to receive(:trap)

      expect(supervisor.run).to eq(0)
      expect(Signal).to have_received(:trap).with('INT', 'DEFAULT')
      expect(Signal).to have_received(:trap).with('TERM', 'DEFAULT')
      expect(Signal).to have_received(:trap).with('USR1', 'DEFAULT')
      expect(worker_instance).to have_received(:run)
    end

    it 'handles subscription setup failures before shutdown restorers are collected' do
      allow(runtime).to receive(:subscribe_signal).and_raise('boom')

      expect { supervisor.run }.to raise_error(RuntimeError, /boom/)
    end

    it 'releases cleanly without writing stopped state when startup fails before a claim is established' do
      runtime_state_store = instance_double(
        described_class.const_get(:RuntimeStateStore, false),
        write_running: nil,
        write_stopped: nil
      )
      allow(runtime_state_store).to receive(:write_running).and_raise('boom')

      supervisor_with_failing_store = described_class.new(
        queue_store: queue_store,
        worker_id: 'worker-supervisor',
        queues: ['billing'],
        handlers: { 'billing_sync' => -> {} },
        lease_duration: 30,
        processes: 1,
        threads: 1,
        poll_interval: 0,
        max_iterations: 1,
        runtime: runtime,
        runtime_state_store: runtime_state_store,
        child_worker_class: child_worker_class
      )

      expect do
        supervisor_with_failing_store.run
      end.to raise_error(RuntimeError, /boom/)
      expect(runtime_state_store).not_to have_received(:write_stopped)
    end

    it 'waits for an in-flight control request to finish before persisting stopped state' do
      runtime_state_store = instance_double(
        described_class.const_get(:RuntimeStateStore, false),
        snapshot: instance_double(described_class.const_get(:RuntimeSnapshot, false), phase: 'running'),
        write_stopped: nil
      )
      runtime_control_server = instance_double(
        described_class.const_get(:RuntimeControlServer, false),
        stop: nil
      )
      request_started = Queue.new
      request_release = Queue.new
      run_session = instance_double(described_class.const_get(:RunSession, false))
      allow(run_session).to receive(:request_drain) do
        request_started << true
        request_release.pop
      end

      supervisor_with_runtime_state = described_class.new(
        queue_store: queue_store,
        worker_id: 'worker-supervisor',
        queues: ['billing'],
        handlers: { 'billing_sync' => -> {} },
        lease_duration: 30,
        processes: 1,
        threads: 1,
        poll_interval: 0,
        max_iterations: 1,
        runtime: runtime,
        runtime_state_store: runtime_state_store,
        child_worker_class: child_worker_class
      )
      supervisor_with_runtime_state.instance_variable_set(:@run_session, run_session)
      supervisor_with_runtime_state.instance_variable_set(:@runtime_control_server, runtime_control_server)
      supervisor_with_runtime_state.instance_variable_set(:@running_claimed, true)

      request_thread = Thread.new { supervisor_with_runtime_state.begin_drain }
      request_started.pop
      release_thread = Thread.new { supervisor_with_runtime_state.send(:release_run) }

      request_release << true
      request_thread.join
      release_thread.join

      expect(runtime_control_server).to have_received(:stop)
      expect(runtime_state_store).to have_received(:write_stopped)
    end

    it 'installs the wakeup trap before publishing runtime control endpoints and restores it after shutdown' do
      wait_results << [100, success_status]
      event_log = []
      runtime_state_store = instance_double(
        described_class.const_get(:RuntimeStateStore, false),
        control_socket_path: '/tmp/runtime.sock',
        instance_token: 'runtime-token',
        snapshot: instance_double(described_class.const_get(:RuntimeSnapshot, false), phase: 'running')
      )
      runtime_control_server = instance_double(
        described_class.const_get(:RuntimeControlServer, false),
        start: nil,
        stop: nil
      )
      allow(runtime_control_server).to receive(:start).and_return(runtime_control_server)
      allow(described_class.const_get(:RuntimeControlServer, false)).to receive(:new).and_return(runtime_control_server)
      allow(runtime_state_store).to receive(:write_running) { event_log << :write_running }
      allow(runtime_state_store).to receive(:write_stopped) { event_log << :write_stopped }
      allow(runtime_state_store).to receive(:register_child)
      allow(runtime_state_store).to receive(:mark_child_phase)
      allow(runtime_state_store).to receive(:mark_child_stopped)
      allow(Signal).to receive(:trap) do |signal, *args, &_block|
        if signal == 'USR1'
          event_log << (args.empty? ? :trap_registered : :trap_restored)
        end
        'DEFAULT'
      end
      allow(runtime_control_server).to receive(:stop) { event_log << :server_stopped }

      supervisor_with_runtime_state = described_class.new(
        queue_store: queue_store,
        worker_id: 'worker-supervisor',
        queues: ['billing'],
        handlers: { 'billing_sync' => -> {} },
        lease_duration: 30,
        processes: 1,
        threads: 1,
        poll_interval: 0,
        max_iterations: 1,
        runtime: runtime,
        runtime_state_store: runtime_state_store,
        child_worker_class: child_worker_class
      )

      expect(supervisor_with_runtime_state.run).to eq(0)
      expect(event_log.index(:trap_registered)).to be < event_log.index(:write_running)
      expect(event_log.index(:server_stopped)).to be < event_log.index(:trap_restored)
    end

    it 'restores already-subscribed signals when later supervisor subscription setup fails' do
      first_restorer = instance_spy(Proc)
      subscription_count = 0
      allow(runtime).to receive(:subscribe_signal) do |_signal, _handler|
        subscription_count += 1
        raise 'boom' if subscription_count == 2

        -> { first_restorer.call }
      end

      expect { supervisor.run }.to raise_error(RuntimeError, /boom/)
      expect(first_restorer).to have_received(:call)
    end

    it 'forcefully terminates tracked children when a later fork fails and graceful cleanup cannot reap them' do
      poll_wait_results << nil
      wait_results << [100, success_status]
      fork_attempts = 0
      allow(runtime).to receive(:fork_child) do
        fork_attempts += 1
        raise Errno::EAGAIN if fork_attempts == 2

        pid = 100
        forked_pids << pid
        pid
      end

      crashing_supervisor = described_class.new(
        queue_store: queue_store,
        worker_id: 'worker-supervisor',
        queues: ['billing'],
        handlers: { 'billing_sync' => -> {} },
        lease_duration: 30,
        processes: 2,
        threads: 1,
        poll_interval: 0,
        max_iterations: 1,
        runtime: runtime,
        child_worker_class: child_worker_class
      )

      expect { crashing_supervisor.run }.to raise_error(Errno::EAGAIN)
      expect(killed_processes).to eq([['TERM', 100], ['KILL', 100]])
      expect(runtime).to have_received(:poll_for_child_exit)
    end

    it 'does not escalate cleanup when graceful cleanup reaps the tracked child immediately' do
      poll_wait_results << [100, success_status]
      fork_attempts = 0
      allow(runtime).to receive(:fork_child) do
        fork_attempts += 1
        raise Errno::EAGAIN if fork_attempts == 2

        pid = 100
        forked_pids << pid
        pid
      end

      crashing_supervisor = described_class.new(
        queue_store: queue_store,
        worker_id: 'worker-supervisor',
        queues: ['billing'],
        handlers: { 'billing_sync' => -> {} },
        lease_duration: 30,
        processes: 2,
        threads: 1,
        poll_interval: 0,
        max_iterations: 1,
        runtime: runtime,
        child_worker_class: child_worker_class
      )

      expect { crashing_supervisor.run }.to raise_error(Errno::EAGAIN)
      expect(killed_processes).to eq([['TERM', 100]])
    end

    it 'returns from forced cleanup when no child can be reaped after escalation' do
      poll_wait_results << nil
      wait_results << nil
      fork_attempts = 0
      allow(runtime).to receive(:process_alive?).with(100).and_return(false)
      allow(runtime).to receive(:fork_child) do
        fork_attempts += 1
        raise Errno::EAGAIN if fork_attempts == 2

        pid = 100
        forked_pids << pid
        pid
      end

      crashing_supervisor = described_class.new(
        queue_store: queue_store,
        worker_id: 'worker-supervisor',
        queues: ['billing'],
        handlers: { 'billing_sync' => -> {} },
        lease_duration: 30,
        processes: 2,
        threads: 1,
        poll_interval: 0,
        max_iterations: 1,
        runtime: runtime,
        child_worker_class: child_worker_class
      )

      expect { crashing_supervisor.run }.to raise_error(Errno::EAGAIN)
      expect(killed_processes).to eq([['TERM', 100]])
    end

    it 'retries blocking cleanup waits after nil returns until tracked children exit' do
      poll_wait_results << nil
      wait_results.push(nil, [100, success_status])
      fork_attempts = 0
      allow(runtime).to receive(:process_alive?).with(100).and_return(true, true)
      allow(runtime).to receive(:fork_child) do
        fork_attempts += 1
        raise Errno::EAGAIN if fork_attempts == 2

        pid = 100
        forked_pids << pid
        pid
      end

      crashing_supervisor = described_class.new(
        queue_store: queue_store,
        worker_id: 'worker-supervisor',
        queues: ['billing'],
        handlers: { 'billing_sync' => -> {} },
        lease_duration: 30,
        processes: 2,
        threads: 1,
        poll_interval: 0,
        max_iterations: 1,
        runtime: runtime,
        child_worker_class: child_worker_class
      )

      expect { crashing_supervisor.run }.to raise_error(Errno::EAGAIN)
      expect(killed_processes).to eq([['TERM', 100], ['KILL', 100]])
      expect(runtime).to have_received(:wait_for_child).twice
    end
  end

  describe 'configuration validation' do
    it 'rejects control actions before the supervisor has started' do
      expect { supervisor.begin_drain }.to raise_error(Karya::WorkerSupervisor::RuntimeControlUnavailableError, /not running/)
      expect { supervisor.force_stop }.to raise_error(Karya::WorkerSupervisor::RuntimeControlUnavailableError, /not running/)
    end

    it 'rejects construction without a queue_store' do
      expect do
        described_class.new(
          worker_id: 'worker-supervisor',
          queues: ['billing'],
          handlers: { 'billing_sync' => -> {} },
          lease_duration: 30
        )
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /queue_store is required/)
    end

    it 'handles startup failures before a run session has been assigned' do
      allow(described_class.const_get(:ShutdownController, false)).to receive(:new).and_raise('boom')

      expect { supervisor.run }.to raise_error(RuntimeError, /boom/)
    end

    it 'does not mark the runtime stopped when startup fails before the state file is claimed' do
      runtime_state_store = instance_double(
        described_class.const_get(:RuntimeStateStore, false),
        write_running: nil,
        write_stopped: nil
      )
      allow(runtime_state_store).to receive(:write_running).and_raise(
        Karya::WorkerSupervisor::RuntimeControlUnavailableError,
        'runtime state file is already owned'
      )

      supervisor_with_unclaimed_store = described_class.new(
        queue_store: queue_store,
        worker_id: 'worker-supervisor',
        queues: ['billing'],
        handlers: { 'billing_sync' => -> {} },
        lease_duration: 30,
        processes: 1,
        threads: 1,
        poll_interval: 0,
        max_iterations: 1,
        runtime: runtime,
        runtime_state_store: runtime_state_store,
        child_worker_class: child_worker_class
      )

      expect do
        supervisor_with_unclaimed_store.run
      end.to raise_error(Karya::WorkerSupervisor::RuntimeControlUnavailableError, /already owned/)
      expect(runtime_state_store).not_to have_received(:write_stopped)
    end

    it 'rejects non-positive processes' do
      expect do
        described_class.new(
          queue_store: queue_store,
          worker_id: 'worker-supervisor',
          queues: ['billing'],
          handlers: { 'billing_sync' => -> {} },
          lease_duration: 30,
          processes: 0
        )
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /processes must be a positive Integer/)
    end

    it 'rejects non-integer processes' do
      expect do
        described_class.new(
          queue_store: queue_store,
          worker_id: 'worker-supervisor',
          queues: ['billing'],
          handlers: { 'billing_sync' => -> {} },
          lease_duration: 30,
          processes: 1.5
        )
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /processes must be a positive Integer/)
    end

    it 'rejects non-positive threads' do
      expect do
        described_class.new(
          queue_store: queue_store,
          worker_id: 'worker-supervisor',
          queues: ['billing'],
          handlers: { 'billing_sync' => -> {} },
          lease_duration: 30,
          threads: 0
        )
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /threads must be a positive Integer/)
    end

    it 'rejects non-boolean stop_when_idle' do
      expect do
        described_class.new(
          queue_store: queue_store,
          worker_id: 'worker-supervisor',
          queues: ['billing'],
          handlers: { 'billing_sync' => -> {} },
          lease_duration: 30,
          stop_when_idle: 'yes'
        )
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /stop_when_idle must be a boolean/)
    end

    it 'rejects missing required configuration keys with the supervisor error class' do
      expect do
        described_class.new(
          queue_store: queue_store,
          queues: ['billing'],
          handlers: { 'billing_sync' => -> {} },
          lease_duration: 30
        )
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /worker_id is required/)
    end

    it 'rejects invalid max_iterations with the supervisor error class' do
      expect do
        described_class.new(
          queue_store: queue_store,
          worker_id: 'worker-supervisor',
          queues: ['billing'],
          handlers: { 'billing_sync' => -> {} },
          lease_duration: 30,
          max_iterations: 'bad'
        )
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /max_iterations must be a positive Integer/)
    end

    it 'rejects false max_iterations with the supervisor error class' do
      expect do
        described_class.new(
          queue_store: queue_store,
          worker_id: 'worker-supervisor',
          queues: ['billing'],
          handlers: { 'billing_sync' => -> {} },
          lease_duration: 30,
          max_iterations: false
        )
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /max_iterations must be a positive Integer/)
    end

    it 'rejects blank worker ids with the supervisor error class' do
      expect do
        described_class.new(
          queue_store: queue_store,
          worker_id: ' ',
          queues: ['billing'],
          handlers: { 'billing_sync' => -> {} },
          lease_duration: 30
        )
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /worker_id must be present/)
    end

    it 'rejects empty queue lists with the supervisor error class' do
      expect do
        described_class.new(
          queue_store: queue_store,
          worker_id: 'worker-supervisor',
          queues: [],
          handlers: { 'billing_sync' => -> {} },
          lease_duration: 30
        )
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /queues must be present/)
    end

    it 'rejects duplicate queue names with the supervisor error class' do
      expect do
        described_class.new(
          queue_store: queue_store,
          worker_id: 'worker-supervisor',
          queues: ['billing', ' billing '],
          handlers: { 'billing_sync' => -> {} },
          lease_duration: 30
        )
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /queues must be unique: billing/)
    end

    it 'rejects non-hash handlers with the supervisor error class' do
      expect do
        described_class.new(
          queue_store: queue_store,
          worker_id: 'worker-supervisor',
          queues: ['billing'],
          handlers: [],
          lease_duration: 30
        )
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /handlers must be a Hash/)
    end

    it 'rejects empty handlers with the supervisor error class' do
      expect do
        described_class.new(
          queue_store: queue_store,
          worker_id: 'worker-supervisor',
          queues: ['billing'],
          handlers: {},
          lease_duration: 30
        )
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /handlers must be present/)
    end

    it 'rejects handlers that collide after name normalization with the supervisor error class' do
      expect do
        described_class.new(
          queue_store: queue_store,
          worker_id: 'worker-supervisor',
          queues: ['billing'],
          handlers: { 'billing_sync' => -> {}, ' billing_sync ' => -> {} },
          lease_duration: 30
        )
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /handlers must be unique: billing_sync/)
    end

    it 'rejects non-positive lease durations with the supervisor error class' do
      expect do
        described_class.new(
          queue_store: queue_store,
          worker_id: 'worker-supervisor',
          queues: ['billing'],
          handlers: { 'billing_sync' => -> {} },
          lease_duration: 0
        )
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /lease_duration must be a positive finite number/)
    end

    it 'rejects invalid lifecycle collaborators with the supervisor error class' do
      expect do
        described_class.new(
          queue_store: queue_store,
          worker_id: 'worker-supervisor',
          queues: ['billing'],
          handlers: { 'billing_sync' => -> {} },
          lease_duration: 30,
          lifecycle: Object.new
        )
      end.to raise_error(
        Karya::InvalidWorkerSupervisorConfigurationError,
        /lifecycle must respond to #normalize_state, #validate_state!, #valid_transition\?, #validate_transition!, #terminal\?/
      )
    end

    it 'rejects negative poll intervals with the supervisor error class' do
      expect do
        described_class.new(
          queue_store: queue_store,
          worker_id: 'worker-supervisor',
          queues: ['billing'],
          handlers: { 'billing_sync' => -> {} },
          lease_duration: 30,
          poll_interval: -1
        )
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /poll_interval must be a finite non-negative number/)
    end

    it 'rejects unknown keyword options' do
      expect do
        described_class.new(
          queue_store: queue_store,
          worker_id: 'worker-supervisor',
          queues: ['billing'],
          handlers: { 'billing_sync' => -> {} },
          lease_duration: 30,
          tracer: Object.new
        )
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /unknown keyword options: tracer/)
    end
  end

  describe 'internal helpers' do
    it 'rescues missing child processes during shutdown signaling' do
      allow(runtime).to receive(:kill_process).and_raise(Errno::ESRCH)
      wait_call_count = 0
      allow(runtime).to receive(:wait_for_child) do
        wait_call_count += 1
        subscriptions.fetch('TERM').call if wait_call_count == 1
        wait_results.shift
      end
      wait_results.push(nil, [100, success_status])

      expect(supervisor.run).to eq(0)
    end

    it 'emits instrumentation for child lifecycle events' do
      wait_results << [100, success_status]

      expect(supervisor.run).to eq(0)

      expect(runtime).to have_received(:instrument).with(
        'supervisor.child.spawned',
        hash_including(worker_id: 'worker-supervisor', pid: 100)
      )
      expect(runtime).to have_received(:instrument).with(
        'supervisor.child.exited',
        hash_including(worker_id: 'worker-supervisor', pid: 100, success: true)
      )
    end

    it 'does not change bounded child state when no stale children were pruned' do
      shutdown_controller = described_class.const_get(:ShutdownController, false).new

      completed_children, failed_bounded_child = supervisor.send(
        :update_pruned_child_state,
        completed_children: 1,
        failed_bounded_child: false,
        pruned_children: [],
        shutdown_controller: shutdown_controller
      )

      expect(completed_children).to eq(1)
      expect(failed_bounded_child).to be(false)
    end

    it 'does not count pruned children after shutdown has started' do
      shutdown_controller = described_class.const_get(:ShutdownController, false).new
      shutdown_controller.advance

      completed_children, failed_bounded_child = supervisor.send(
        :update_pruned_child_state,
        completed_children: 1,
        failed_bounded_child: false,
        pruned_children: [100],
        shutdown_controller: shutdown_controller
      )

      expect(completed_children).to eq(1)
      expect(failed_bounded_child).to be(false)
    end

    it 'ignores waited child pids that are not tracked during helper reaping' do
      child_pids = { 100 => true }
      waited_children = [[999, success_status], nil]

      supervisor.send(:reap_tracked_children, child_pids, blocking: false) do
        waited_children.shift
      end

      expect(child_pids.keys).to eq([100])
    end

    it 'continues blocking helper reaping after unknown waited child pids' do
      child_pids = { 100 => true }
      waited_children = [[999, success_status], nil]

      allow(runtime).to receive(:process_alive?).with(100).and_return(false)

      supervisor.send(:reap_tracked_children, child_pids, blocking: true) do
        waited_children.shift
      end

      expect(child_pids).to be_empty
      expect(runtime).to have_received(:process_alive?).with(100)
    end
  end

  describe 'runtime control dispatch' do
    it 'dispatches drain and force-stop commands and rejects unknown commands' do
      supervisor_class = Class.new(described_class) do
        attr_reader :runtime_commands

        def begin_drain
          (@runtime_commands ||= []) << :drain
        end

        def force_stop
          (@runtime_commands ||= []) << :force_stop
        end
      end
      command_supervisor = supervisor_class.new(
        queue_store: queue_store,
        worker_id: 'worker-supervisor',
        queues: ['billing'],
        handlers: { 'billing_sync' => -> {} },
        lease_duration: 30,
        processes: processes,
        threads: threads,
        poll_interval: 0,
        max_iterations: max_iterations,
        stop_when_idle: stop_when_idle,
        runtime: runtime,
        child_worker_class: child_worker_class
      )

      command_supervisor.send(:handle_runtime_control_command, 'drain')
      command_supervisor.send(:handle_runtime_control_command, 'force_stop')

      expect(command_supervisor.runtime_commands).to eq(%i[drain force_stop])
      expect do
        command_supervisor.send(:handle_runtime_control_command, 'noop')
      end.to raise_error(Karya::WorkerSupervisor::InvalidRuntimeStateFileError, /unsupported runtime control command: noop/)
    end
  end

  describe 'wait-loop wakeup' do
    it 'ignores missing current processes when interrupting the wait loop' do
      wakeup_signal_class = described_class.const_get(:WakeupSignal, false)
      allow(Process).to receive(:kill).with('USR1', Process.pid).and_raise(Errno::ESRCH)

      expect(wakeup_signal_class.interrupt('USR1')).to be_nil
    end
  end
end
