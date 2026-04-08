# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'tmpdir'
require 'fileutils'

RSpec.describe 'Karya::WorkerSupervisor::Runtime' do
  let(:runtime_class) { Karya::WorkerSupervisor.const_get(:Runtime, false) }
  let(:success_status) { instance_double(Process::Status, success?: true) }
  let(:failure_status) { instance_double(Process::Status, success?: false) }

  describe 'integration tests' do
    it 'builds and runs a real child worker from supervisor configuration' do
      real_queue_store = Karya::QueueStore::InMemory.new(token_generator: -> { 'lease-token' })
      executed = []
      real_runtime = instance_double(
        runtime_class,
        instrument: nil,
        signal_subscriber: nil,
        subscribe_signal: nil,
        fork_child: nil,
        poll_for_child_exit: nil,
        wait_for_child: nil,
        kill_process: nil
      )
      allow(real_runtime).to receive_messages(
        subscribe_signal: -> {},
        poll_for_child_exit: nil,
        wait_for_child: [123, success_status]
      )
      allow(real_runtime).to receive(:fork_child) do |&block|
        block.call
        123
      end
      allow(real_runtime).to receive(:kill_process)
      real_queue_store.enqueue(
        job: Karya::Job.new(
          id: 'job-1',
          queue: 'billing',
          handler: 'billing_sync',
          arguments: { 'account_id' => 42 },
          state: :submission,
          created_at: Time.utc(2026, 3, 29, 12, 0, 0)
        ),
        now: Time.utc(2026, 3, 29, 12, 0, 0)
      )

      result = Karya::WorkerSupervisor.new(
        queue_store: real_queue_store,
        worker_id: 'worker-supervisor',
        queues: ['billing'],
        handlers: { 'billing_sync' => ->(account_id:) { executed << account_id } },
        lease_duration: 30,
        processes: 1,
        threads: 1,
        poll_interval: 0,
        max_iterations: 1,
        runtime: real_runtime
      ).run

      expect(result).to eq(0)
      expect(executed).to eq([42])
      job = real_queue_store.instance_variable_get(:@state).jobs_by_id.fetch('job-1')
      expect(job.state).to eq(:succeeded)
    end

    it 'runs real child workers in unlimited mode by passing nil max_iterations to Worker' do
      real_queue_store = Karya::QueueStore::InMemory.new(token_generator: -> { 'lease-token' })
      executed = []
      real_runtime = instance_double(
        runtime_class,
        instrument: nil,
        signal_subscriber: nil,
        subscribe_signal: nil,
        fork_child: nil,
        poll_for_child_exit: nil,
        wait_for_child: nil,
        kill_process: nil
      )
      allow(real_runtime).to receive_messages(
        subscribe_signal: -> {},
        poll_for_child_exit: nil,
        wait_for_child: [123, success_status]
      )
      allow(real_runtime).to receive(:fork_child) do |&block|
        block.call
        123
      end
      allow(real_runtime).to receive(:kill_process)
      now = Time.utc(2026, 3, 29, 12, 0, 0)
      real_queue_store.enqueue(
        job: Karya::Job.new(
          id: 'job-1',
          queue: 'billing',
          handler: 'billing_sync',
          arguments: { 'account_id' => 42 },
          state: :submission,
          created_at: now
        ),
        now: now
      )

      result = Karya::WorkerSupervisor.new(
        queue_store: real_queue_store,
        worker_id: 'worker-supervisor',
        queues: ['billing'],
        handlers: { 'billing_sync' => ->(account_id:) { executed << account_id } },
        lease_duration: 30,
        processes: 1,
        threads: 1,
        poll_interval: 0,
        stop_when_idle: true,
        runtime: real_runtime
      ).run

      expect(result).to eq(0)
      expect(executed).to eq([42])
      job = real_queue_store.instance_variable_get(:@state).jobs_by_id.fetch('job-1')
      expect(job.state).to eq(:succeeded)
    end
  end

  describe 'unit tests' do
    it 'covers runtime defaults and no-op signal subscriptions' do
      runtime_instance = runtime_class.new
      noop = runtime_instance.subscribe_signal('TERM', -> {})
      pid = runtime_instance.fork_child { 1 }
      waited_pid, waited_status = runtime_instance.wait_for_child

      expect(noop).to respond_to(:call)
      expect(pid).to be_a(Integer)
      expect(waited_pid).to eq(pid)
      expect(waited_status.success?).to be(true)
    end

    it 'accepts runtime hooks through Ruby keyword arguments' do
      forker = lambda do |&block|
        block.call
        123
      end

      runtime_instance = runtime_class.new(forker:)

      waited_pid = runtime_instance.fork_child { :ok }

      expect(waited_pid).to eq(123)
    end

    it 'returns nil when the default poll waiter has no child process' do
      expect(runtime_class.new.poll_for_child_exit).to be_nil
    end

    it 'uses default killer that calls Process.kill when killer is not provided' do
      runtime_instance = runtime_class.new
      allow(Process).to receive(:kill)
      runtime_instance.kill_process('TERM', 12_345)
      expect(Process).to have_received(:kill).with('TERM', 12_345)
    end

    it 'reports processes as alive when Process.kill succeeds' do
      runtime_instance = runtime_class.new
      allow(Process).to receive(:kill).with(0, 12_345).and_return(1)

      expect(runtime_instance.process_alive?(12_345)).to be(true)
    end

    it 'reports processes as alive when kill raises EPERM' do
      runtime_instance = runtime_class.new
      allow(Process).to receive(:kill).with(0, 12_345).and_raise(Errno::EPERM)

      expect(runtime_instance.process_alive?(12_345)).to be(true)
    end

    it 'reports processes as dead when kill raises ESRCH' do
      runtime_instance = runtime_class.new
      allow(Process).to receive(:kill).with(0, 12_345).and_raise(Errno::ESRCH)

      expect(runtime_instance.process_alive?(12_345)).to be(false)
    end

    it 'retries the default poll waiter when waits are interrupted' do
      runtime_instance = runtime_class.new
      call_count = 0
      allow(Process).to receive(:wait2) do
        call_count += 1
        raise Errno::EINTR if call_count == 1

        [123, success_status]
      end

      expect(runtime_instance.poll_for_child_exit).to eq([123, success_status])
      expect(Process).to have_received(:wait2).with(-1, Process::WNOHANG).twice
    end

    it 'returns nil when the default waiter has no child process' do
      expect(runtime_class.new.wait_for_child).to be_nil
    end

    it 'returns nil from the default waiter when waits are interrupted' do
      runtime_instance = runtime_class.new
      allow(Process).to receive(:wait2).and_raise(Errno::EINTR)

      expect(runtime_instance.wait_for_child).to be_nil
      expect(Process).to have_received(:wait2).with(-1).once
    end

    it 'lets Interrupt bubble from the default waiter' do
      runtime_instance = runtime_class.new
      allow(Process).to receive(:wait2).and_raise(Interrupt)

      expect { runtime_instance.wait_for_child }.to raise_error(Interrupt)
    end

    it 'covers runtime failure exits for child blocks' do
      runtime_instance = runtime_class.new
      pid = runtime_instance.fork_child { raise 'boom' }
      waited_pid, waited_status = runtime_instance.wait_for_child

      expect(waited_pid).to eq(pid)
      expect(waited_status.success?).to be(false)
    end

    it 'runs the default forker block in the child process before exiting successfully' do
      runtime_instance = runtime_class.new
      marker_dir = Dir.mktmpdir('karya-default-forker')
      marker_path = File.join(marker_dir, 'child-ran.txt')

      begin
        pid = runtime_instance.fork_child do
          File.write(marker_path, Process.pid.to_s)
        end
        waited_pid, waited_status = runtime_instance.wait_for_child

        expect(waited_pid).to eq(pid)
        expect(waited_status.success?).to be(true)
        expect(File.read(marker_path).strip).to eq(pid.to_s)
      ensure
        FileUtils.rm_f(marker_path)
        FileUtils.remove_dir(marker_dir)
      end
    end

    it 'covers the default forker success path without forking a real process' do
      runtime_instance = runtime_class.new
      allow(Process).to receive(:fork).and_yield.and_return(123)
      allow(Kernel).to receive(:exit!)

      expect(runtime_instance.send(:default_forker) { :ok }).to eq(123)
      expect(Kernel).to have_received(:exit!).with(0)
    end

    it 're-raises SystemExit from the default forker child block' do
      runtime_instance = runtime_class.new
      allow(Process).to receive(:fork).and_yield

      expect do
        runtime_instance.send(:default_forker) { raise SystemExit, 1 }
      end.to raise_error(SystemExit)
    end

    it 'covers the default forker failure path without forking a real process' do
      runtime_instance = runtime_class.new
      allow(Process).to receive(:fork).and_yield
      allow(Kernel).to receive(:exit!)

      runtime_instance.send(:default_forker) { raise 'boom' }

      expect(Kernel).to have_received(:exit!).with(1)
    end

    it 'builds runtime from option hashes and restores nil restorer handling' do
      subscriptions = {}
      runtime_instance = runtime_class.from_options(
        forker: lambda do |&block|
          block.call
          123
        end,
        killer: ->(signal, pid) { [signal, pid] },
        poll_waiter: -> { [123, success_status] },
        signal_subscriber: lambda do |signal, handler|
          subscriptions[signal] = handler
          nil
        end,
        waiter: -> { [123, success_status] }
      )

      noop = runtime_instance.subscribe_signal('TERM', -> {})
      expect(runtime_instance.fork_child { 1 }).to eq(123)
      expect(runtime_instance.kill_process('TERM', 123)).to eq(['TERM', 123])
      expect(runtime_instance.poll_for_child_exit).to eq([123, success_status])
      expect(runtime_instance.wait_for_child).to eq([123, success_status])
      expect(noop).to respond_to(:call)
      expect(subscriptions.keys).to eq(['TERM'])
    end

    it 'rejects non-callable signal subscriber restorers' do
      runtime_instance = runtime_class.new(signal_subscriber: ->(_signal, _handler) { 'DEFAULT' })

      expect do
        runtime_instance.subscribe_signal('TERM', -> {})
      end.to raise_error(
        Karya::InvalidWorkerSupervisorConfigurationError,
        /signal_subscriber must return a callable restorer responding to #call/
      )
    end

    it 'rejects false signal subscriber restorers' do
      runtime_instance = runtime_class.new(signal_subscriber: ->(_signal, _handler) { false })

      expect do
        runtime_instance.subscribe_signal('TERM', -> {})
      end.to raise_error(
        Karya::InvalidWorkerSupervisorConfigurationError,
        /signal_subscriber must return a callable restorer responding to #call/
      )
    end

    it 'returns callable signal subscriber restorers unchanged' do
      restorer = -> {}
      runtime_instance = runtime_class.new(signal_subscriber: ->(_signal, _handler) { restorer })

      expect(runtime_instance.subscribe_signal('TERM', -> {})).to be(restorer)
    end

    it 'raises the supervisor error class for invalid runtime callables' do
      expect do
        runtime_class.new(forker: Object.new)
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /forker must respond to #call/)
    end

    it 'rejects signal_subscriber set to false for supervisor runtime' do
      expect do
        runtime_class.new(signal_subscriber: false)
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /signal_subscriber must respond to #call/)
    end

    it 'rejects instrumenter set to false for supervisor runtime' do
      expect do
        runtime_class.new(instrumenter: false)
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /instrumenter must respond to #call/)
    end

    it 'rejects forker set to false for supervisor runtime' do
      expect do
        runtime_class.new(forker: false)
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /forker must respond to #call/)
    end

    it 'rejects logger set to false for supervisor runtime' do
      expect do
        runtime_class.new(logger: false)
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /logger must respond to #debug, #info, #warn, and #error/)
    end

    it 'returns nil when no instrumenter is configured' do
      expect(runtime_class.new.instrument('supervisor.child.spawned', pid: 123)).to be_nil
    end

    it 'emits instrumentation through the configured instrumenter' do
      instrumented_events = []
      runtime_instance = runtime_class.new(
        instrumenter: ->(event, payload) { instrumented_events << [event, payload] }
      )

      runtime_instance.instrument('supervisor.child.spawned', pid: 123)

      expect(instrumented_events).to eq([['supervisor.child.spawned', { pid: 123 }]])
    end

    it 'swallows instrumentation errors and logs them' do
      logger = instance_double(Karya::Internal::NullLogger, debug: nil, info: nil, warn: nil, error: nil)
      runtime_instance = runtime_class.new(
        instrumenter: ->(_event, _payload) { raise 'boom' },
        logger:
      )

      expect(runtime_instance.instrument('supervisor.child.spawned', pid: 123)).to be_nil
      expect(logger).to have_received(:error).with(
        'instrumentation failed',
        event: 'supervisor.child.spawned',
        error_class: 'RuntimeError',
        error_message: 'boom'
      )
    end
  end
end
