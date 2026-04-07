# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'tmpdir'
require 'json'
require 'fileutils'
require 'socket'

RSpec.describe Karya::WorkerSupervisor::RuntimeStateStore do
  let(:configuration) do
    Karya::WorkerSupervisor.const_get(:Configuration, false).new(
      worker_id: 'worker-supervisor',
      queues: ['billing'],
      handlers: { 'billing_sync' => -> {} },
      lease_duration: 30,
      processes: 1,
      threads: 2
    )
  end

  let(:state_dir) { Dir.mktmpdir('karya-runtime-store') }
  let(:state_file) { File.join(state_dir, 'runtime.json') }
  let(:socket_file) { File.join(state_dir, 'runtime.sock') }

  after do
    FileUtils.rm_rf(state_dir)
  end

  def runtime_payload(phase: 'running', supervisor_pid: 12_345, child_processes: [], instance_token: 'runtime-token', control_socket_path: socket_file)
    {
      schema_version: 1,
      updated_at: Time.utc(2026, 4, 2, 12, 0, 0).iso8601,
      started_at: Time.utc(2026, 4, 2, 12, 0, 0).iso8601,
      instance_token:,
      control_socket_path:,
      supervisor_pid:,
      snapshot: {
        worker_id: 'worker-supervisor',
        supervisor_pid:,
        queues: ['billing'],
        configured_processes: 1,
        configured_threads: 1,
        phase:,
        child_processes:
      }
    }
  end

  it 'exposes a no-op null store for isolated callers' do
    store = described_class::NullStore.new

    expect(store.snapshot.phase).to eq('stopped')
    store.write_running
    store.mark_supervisor_phase('running')
    store.register_child(123)
    store.mark_child_phase(123, 'draining')
    store.mark_child_stopped(123)
    store.register_thread(process_pid: 123, worker_id: 'worker-1', thread_index: 1)
    store.mark_thread_state(process_pid: 123, worker_id: 'worker-1', state: 'running', thread_index: 1)
    store.write_stopped
  end

  it 'normalizes snapshots from symbol-keyed payloads and serializes them back to hashes' do
    snapshot = Karya::WorkerSupervisor::RuntimeSnapshot.from_h(
      worker_id: 'worker-supervisor',
      supervisor_pid: 123,
      queues: ['billing'],
      configured_processes: 1,
      configured_threads: 2,
      phase: 'running',
      child_processes: [
        {
          pid: 123,
          state: 'running',
          thread_count: 2,
          threads: [
            { worker_id: 'worker-supervisor:123:thread-1', state: 'polling' }
          ]
        }
      ]
    )

    expect(snapshot.to_h).to eq(
      worker_id: 'worker-supervisor',
      supervisor_pid: 123,
      queues: ['billing'],
      configured_processes: 1,
      configured_threads: 2,
      phase: 'running',
      child_processes: [
        {
          pid: 123,
          state: 'running',
          thread_count: 2,
          threads: [
            { worker_id: 'worker-supervisor:123:thread-1', state: 'polling' }
          ]
        }
      ]
    )
  end

  it 'defaults optional child and thread collections when they are omitted' do
    snapshot = Karya::WorkerSupervisor::RuntimeSnapshot.from_h(
      worker_id: 'worker-supervisor',
      supervisor_pid: 123,
      queues: ['billing'],
      configured_processes: 1,
      configured_threads: 2,
      phase: 'running'
    )

    expect(snapshot.child_processes).to eq([])
  end

  it 'detects stale runtime payloads and accepts stopped payloads for dead processes' do
    stale_payload = runtime_payload
    File.write(state_file, JSON.pretty_generate(stale_payload))
    allow(Process).to receive(:kill).with(0, 12_345).and_raise(Errno::ESRCH)

    expect do
      described_class.live_payload!(state_file)
    end.to raise_error(Karya::WorkerSupervisor::InvalidRuntimeStateFileError, /stale/)

    stale_payload[:snapshot][:phase] = 'stopped'
    File.write(state_file, JSON.pretty_generate(stale_payload))

    expect(described_class.live_payload!(state_file).fetch('snapshot').fetch('phase')).to eq('stopped')
  end

  it 'treats a running payload as stale when the pid exists but the control socket does not' do
    File.write(state_file, JSON.pretty_generate(runtime_payload))
    allow(Process).to receive(:kill).with(0, 12_345).and_return(1)

    expect do
      described_class.live_payload!(state_file)
    end.to raise_error(Karya::WorkerSupervisor::InvalidRuntimeStateFileError, /stale/)
  end

  it 'treats a running payload as stale when the pid exists but the control token no longer matches the socket owner' do
    server = UNIXServer.new(socket_file)
    File.write(state_file, JSON.pretty_generate(runtime_payload(instance_token: 'stale-token')))
    allow(Process).to receive(:kill).with(0, 12_345).and_return(1)
    server_thread = Thread.new do
      client = server.accept
      JSON.parse(client.read)
      client.write(JSON.generate('error' => 'runtime control token does not match the running supervisor'))
      client.close
    ensure
      server.close
    end

    expect do
      described_class.live_payload!(state_file)
    end.to raise_error(Karya::WorkerSupervisor::InvalidRuntimeStateFileError, /stale/)
  ensure
    server_thread&.join
    FileUtils.rm_f(socket_file)
  end

  it 'treats a running payload as stale when the control socket returns malformed JSON' do
    server = UNIXServer.new(socket_file)
    File.write(state_file, JSON.pretty_generate(runtime_payload))
    allow(Process).to receive(:kill).with(0, 12_345).and_return(1)
    server_thread = Thread.new do
      client = server.accept
      client.read
      client.write('{')
      client.close
    ensure
      server.close
    end

    expect do
      described_class.live_payload!(state_file)
    end.to raise_error(Karya::WorkerSupervisor::InvalidRuntimeStateFileError, /stale/)
  ensure
    server_thread&.join
    FileUtils.rm_f(socket_file)
  end

  it 'returns an empty control response buffer when the socket never becomes readable' do
    socket = instance_double(IO, wait_readable: nil)

    expect(described_class.send(:read_control_response, socket)).to eq('')
  end

  def expect_invalid_payload(payload, message)
    File.write(state_file, JSON.pretty_generate(payload))

    expect do
      described_class.read_payload!(state_file)
    end.to raise_error(Karya::WorkerSupervisor::InvalidRuntimeStateFileError, message)
  end

  it 'rejects invalid JSON, unsupported schemas, and missing required keys' do
    expect do
      described_class.read_payload!(nil)
    end.to raise_error(Karya::WorkerSupervisor::InvalidRuntimeStateFileError, /path is required/)

    File.write(state_file, '{')
    expect do
      described_class.read_payload!(state_file)
    end.to raise_error(Karya::WorkerSupervisor::InvalidRuntimeStateFileError, /not valid JSON/)

    expect_invalid_payload(runtime_payload.merge(schema_version: 2), /unsupported schema/)
    expect_invalid_payload(runtime_payload.tap { |payload| payload.delete(:snapshot) }, /missing "snapshot"/)
    expect_invalid_payload(runtime_payload.tap { |payload| payload[:snapshot].delete(:phase) }, /snapshot is missing "phase"/)
  end

  it 'rejects invalid top-level runtime state field types' do
    expect_invalid_payload(runtime_payload.merge(updated_at: 123), /updated_at must be a String/)
    expect_invalid_payload(runtime_payload.merge(started_at: 123), /started_at must be a String/)
    expect_invalid_payload(runtime_payload.merge(instance_token: 123), /instance_token must be a String/)
    expect_invalid_payload(runtime_payload.merge(control_socket_path: 123), /control_socket_path must be a String/)
    expect_invalid_payload(runtime_payload.merge(supervisor_pid: '123'), /supervisor_pid must be an Integer/)
  end

  it 'rejects malformed snapshot header fields' do
    expect_invalid_payload(runtime_payload.merge(snapshot: 'bad-snapshot'), /snapshot must be a Hash/)
    expect_invalid_payload(runtime_payload.tap { |payload| payload[:snapshot][:worker_id] = 123 }, /worker_id must be a String/)
    expect_invalid_payload(runtime_payload.tap { |payload| payload[:snapshot][:supervisor_pid] = '123' }, /snapshot supervisor_pid must be an Integer/)
    expect_invalid_payload(runtime_payload.tap { |payload| payload[:snapshot][:queues] = 'billing' }, /queues must be an Array/)
    expect_invalid_payload(runtime_payload.tap { |payload| payload[:snapshot][:queues] = ['billing', 1] }, /queues entries must all be Strings/)
    expect_invalid_payload(runtime_payload.tap { |payload| payload[:snapshot][:configured_processes] = '1' }, /configured_processes must be an Integer/)
    expect_invalid_payload(runtime_payload.tap { |payload| payload[:snapshot][:configured_threads] = '1' }, /configured_threads must be an Integer/)
    expect_invalid_payload(runtime_payload.tap { |payload| payload[:snapshot][:phase] = 'mystery' }, /phase must be one of:/)
  end

  it 'rejects malformed child runtime snapshots' do
    expect_invalid_payload(
      runtime_payload.tap { |payload| payload[:snapshot][:child_processes] = 'bad-children' },
      /child_processes must be an Array/
    )
    expect_invalid_payload(runtime_payload(child_processes: ['bad-child']), /child snapshot must be a Hash/)
    expect_invalid_payload(
      runtime_payload(child_processes: [{ pid: '12_345', state: 'running', thread_count: 1, threads: [] }]),
      /child pid must be an Integer/
    )
    expect_invalid_payload(
      runtime_payload(child_processes: [{ pid: 12_345, state: 'mystery', thread_count: 1, threads: [] }]),
      /child state must be one of:/
    )
    expect_invalid_payload(
      runtime_payload(child_processes: [{ pid: 12_345, state: 'running', thread_count: '1', threads: [] }]),
      /child thread_count must be an Integer/
    )
    expect_invalid_payload(
      runtime_payload(child_processes: [{ pid: 12_345, state: 'running', thread_count: 1 }]),
      /child snapshot is missing "threads"/
    )
    expect_invalid_payload(
      runtime_payload(child_processes: [{ pid: 12_345, state: 'running', thread_count: 1, threads: 'bad-threads' }]),
      /child threads must be an Array/
    )
  end

  it 'rejects malformed thread runtime snapshots' do
    expect_invalid_payload(
      runtime_payload(child_processes: [{ pid: 12_345, state: 'running', thread_count: 1, threads: ['bad-thread'] }]),
      /thread snapshot must be a Hash/
    )
    expect_invalid_payload(
      runtime_payload(child_processes: [{ pid: 12_345, state: 'running', thread_count: 1, threads: [{ worker_id: 'worker-1' }] }]),
      /thread snapshot is missing "state"/
    )
    expect_invalid_payload(
      runtime_payload(child_processes: [{ pid: 12_345, state: 'running', thread_count: 1, threads: [{ worker_id: 1, state: 'polling', thread_index: 1 }] }]),
      /thread worker_id must be a String/
    )
    expect_invalid_payload(
      runtime_payload(
        child_processes: [
          { pid: 12_345, state: 'running', thread_count: 1, threads: [{ worker_id: 'worker-1', state: 'mystery', thread_index: 1 }] }
        ]
      ),
      /thread state must be one of:/
    )
    expect_invalid_payload(
      runtime_payload(child_processes: [{ pid: 12_345, state: 'running', thread_count: 1, threads: [{ worker_id: 'worker-1', state: 'polling' }] }]),
      /thread snapshot is missing "thread_index"/
    )
    expect_invalid_payload(
      runtime_payload(
        child_processes: [{ pid: 12_345, state: 'running', thread_count: 1, threads: [{ worker_id: 'worker-1', state: 'polling', thread_index: '1' }] }]
      ),
      /thread_index must be an Integer/
    )
  end

  it 'reports process liveness for EPERM and ESRCH failures' do
    allow(Process).to receive(:kill).with(0, 12_345).and_raise(Errno::EPERM)
    expect(described_class.process_alive?(12_345)).to be(true)

    allow(Process).to receive(:kill).with(0, 67_890).and_raise(Errno::ESRCH)
    expect(described_class.process_alive?(67_890)).to be(false)
  end

  it 'derives the default state-file path even when the worker id slug is empty' do
    expect(described_class.default_path('!!!')).to end_with("/karya-runtime-worker-#{Process.pid}.json")
  end

  it 'includes the current pid in the default state-file path to avoid collisions between concurrent supervisors' do
    expect(described_class.default_path('billing-worker')).to end_with("/karya-runtime-billing-worker-#{Process.pid}.json")
  end

  it 'writes, snapshots, and controls runtime payloads through the state file' do
    server = UNIXServer.new(socket_file)
    store = described_class.new(configuration:, path: state_file, supervisor_pid: 12_345)
    store.write_running
    store.register_child(12_345)
    store.register_thread(process_pid: 12_345, worker_id: 'worker-supervisor:12345:thread-1', thread_index: 1)
    store.mark_thread_state(process_pid: 12_345, worker_id: 'worker-supervisor:12345:thread-1', state: 'polling')
    store.mark_child_phase(12_345, 'draining')
    store.mark_child_stopped(12_345)
    store.write_stopped

    snapshot = described_class.read_snapshot!(state_file)
    expect(snapshot.phase).to eq('stopped')
    expect(snapshot.child_processes.first.to_h).to include(pid: 12_345, state: 'stopped')

    payload = described_class.control_payload!(state_file)
    expect(payload.fetch('supervisor_pid')).to eq(12_345)
    expect(payload.fetch('instance_token')).not_to be_empty
    expect(payload.fetch('control_socket_path')).to eq(socket_file)
  ensure
    server&.close
  end

  it 'does not rewrite a stopped payload back to a live phase' do
    store = described_class.new(configuration:, path: state_file, supervisor_pid: 12_345)
    store.write_running
    store.write_stopped

    expect do
      store.mark_supervisor_phase('draining')
    end.not_to raise_error
    expect(described_class.read_snapshot!(state_file).phase).to eq('stopped')
  end

  it 'starts a stopped child again when the same pid is registered' do
    store = described_class.new(configuration:, path: state_file, supervisor_pid: 12_345)
    store.write_running
    store.register_child(100)
    store.mark_child_stopped(100)
    store.register_child(100)

    snapshot = described_class.read_snapshot!(state_file)
    expect(snapshot.child_processes.map(&:to_h)).to include(include(pid: 100, state: 'running'))
  end

  it 'overwrites instance metadata when a new supervisor starts with an existing state file' do
    first_store = described_class.new(configuration:, path: state_file, supervisor_pid: 12_345)
    first_store.write_running
    first_payload = described_class.read_payload!(state_file)

    second_store = described_class.new(configuration:, path: state_file, supervisor_pid: 54_321)
    allow(described_class).to receive(:process_alive?).with(12_345).and_return(false)
    second_store.write_running
    second_payload = described_class.read_payload!(state_file)

    expect(second_store.instance_token).not_to eq(first_store.instance_token)
    expect(second_payload.fetch('instance_token')).to eq(second_store.instance_token)
    expect(second_payload.fetch('started_at')).to eq(second_store.started_at)
    expect(second_payload.fetch('control_socket_path')).to eq(second_store.control_socket_path)
    expect(second_payload.fetch('supervisor_pid')).to eq(54_321)
    expect(second_payload.fetch('instance_token')).not_to eq(first_payload.fetch('instance_token'))
  end

  it 'defaults thread index inference when the worker id does not end in a thread suffix' do
    store = described_class.new(configuration:, path: state_file, supervisor_pid: 12_345)
    store.write_running
    store.mark_thread_state(process_pid: 12_345, worker_id: 'worker-supervisor:12345', state: 'polling')

    snapshot = described_class.read_snapshot!(state_file)
    expect(snapshot.child_processes.first.thread_count).to eq(2)
    expect(snapshot.child_processes.first.threads.first.worker_id).to eq('worker-supervisor:12345')
  end

  it 'rejects control payload lookups when the supervisor pid is no longer running' do
    File.write(state_file, JSON.pretty_generate(runtime_payload(phase: 'stopped')))

    expect do
      described_class.control_payload!(state_file)
    end.to raise_error(Karya::WorkerSupervisor::InvalidRuntimeStateFileError, /control socket is missing/)
  end

  it 'rejects control payloads whose control path exists but is not a Unix socket' do
    File.write(socket_file, 'not-a-socket')
    File.write(state_file, JSON.pretty_generate(runtime_payload))

    expect do
      described_class.control_payload!(state_file)
    end.to raise_error(Karya::WorkerSupervisor::InvalidRuntimeStateFileError, /not a Unix socket/)
  end

  it 'derives the default socket path from the runtime state path' do
    expect(described_class.default_control_socket_path(state_file)).to end_with('/runtime.sock')
  end

  it 'falls back to a hashed socket path when the adjacent path would exceed platform limits' do
    long_state_file = File.join(state_dir, "#{'x' * 140}.json")
    socket_path = described_class.default_control_socket_path(long_state_file)

    expect(socket_path).to start_with('/tmp/karya-')
    expect(socket_path.bytesize).to be <= described_class::MAX_UNIX_SOCKET_PATH_BYTES
  end

  it 'rejects custom socket paths that exceed platform limits' do
    long_socket_path = File.join('/tmp', "#{'y' * 120}.sock")

    expect do
      described_class.new(configuration:, path: state_file, control_socket_path: long_socket_path)
    end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /socket path is too long/)
  end

  it 'prunes stopped children when newer child pids are registered' do
    store = described_class.new(configuration:, path: state_file, supervisor_pid: 12_345)
    store.write_running
    store.register_child(100)
    store.mark_child_stopped(100)
    store.register_child(101)

    snapshot = described_class.read_snapshot!(state_file)
    expect(snapshot.child_processes.map(&:pid)).to eq([101])
  end

  it 'raises a descriptive error when acquiring the state lock times out' do
    store = described_class.new(configuration:, path: state_file, supervisor_pid: 12_345)
    lock_file = instance_double(File, flock: false)
    monotonic_values = [0.0, 0.5, 1.0]
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { monotonic_values.shift || 1.0 }
    allow(lock_file).to receive(:flock).with(File::LOCK_EX | File::LOCK_NB).and_return(false)
    allow(lock_file).to receive(:flock).with(File::LOCK_UN)
    allow(File).to receive(:open).with("#{state_file}.lock", File::RDWR | File::CREAT, 0o644).and_yield(lock_file)
    allow(store).to receive(:sleep)

    expect do
      store.write_running
    end.to raise_error(Karya::WorkerSupervisor::InvalidRuntimeStateFileError, /timed out acquiring runtime state lock/)
  end

  it 'does not time out after the runtime state lock has been acquired' do
    writer_class = described_class.const_get(:AtomicPayloadWriter, false)
    slow_writer = instance_double(writer_class, write: nil)
    store = described_class.new(configuration:, path: state_file, supervisor_pid: 12_345)
    allow(writer_class).to receive(:new).and_return(slow_writer)
    allow(slow_writer).to receive(:write) { sleep(0.01) }

    expect { store.write_running }.not_to raise_error
  end

  it 'rejects malformed on-disk payloads for incremental updates instead of silently normalizing them' do
    File.write(state_file, JSON.pretty_generate(runtime_payload.merge(snapshot: 'bad-snapshot')))
    store = described_class.new(configuration:, path: state_file, supervisor_pid: 12_345)

    expect do
      store.mark_supervisor_phase('draining')
    end.to raise_error(Karya::WorkerSupervisor::InvalidRuntimeStateFileError, /snapshot must be a Hash/)
  end

  it 'returns a blank payload when the runtime state file is missing' do
    store = described_class.new(configuration:, path: state_file, supervisor_pid: 12_345)

    expect(store.snapshot.phase).to eq('stopped')
  end

  it 'refuses to claim a live runtime state file owned by another supervisor' do
    File.write(state_file, JSON.pretty_generate(runtime_payload(supervisor_pid: 12_345, instance_token: 'other-token')))
    allow(described_class).to receive(:process_alive?).with(12_345).and_return(true)
    store = described_class.new(configuration:, path: state_file, supervisor_pid: 54_321)

    expect do
      store.write_running
    end.to raise_error(Karya::WorkerSupervisor::RuntimeControlUnavailableError, /already owned by live supervisor pid 12345/)
  end

  it 'allows the same live supervisor instance to refresh its own runtime state file' do
    store = described_class.new(
      configuration:,
      path: state_file,
      supervisor_pid: 12_345,
      instance_token: 'same-instance-token'
    )
    allow(described_class).to receive(:process_alive?).with(12_345).and_return(true)

    store.write_running

    expect { store.write_running }.not_to raise_error
  end

  it 'raises an invalid-state error when incremental reads hit malformed JSON' do
    store = described_class.new(configuration:, path: state_file, supervisor_pid: 12_345)
    File.write(state_file, '{')

    expect do
      store.mark_supervisor_phase('draining')
    end.to raise_error(Karya::WorkerSupervisor::InvalidRuntimeStateFileError, /not valid JSON/)
  end
end
