# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'tmpdir'
require 'json'
require 'fileutils'
require 'socket'

RSpec.describe Karya::CLI do
  let(:runtime_command_class) { described_class.const_get(:RuntimeCommand, false) }
  let(:state_dir) { Dir.mktmpdir('karya-runtime-cli') }
  let(:state_file) { File.join(state_dir, 'runtime.json') }
  let(:socket_file) { File.join(state_dir, 'runtime.sock') }

  after do
    FileUtils.rm_f(state_file)
    FileUtils.rm_rf(state_dir)
  end

  def write_state_file(phase: 'running', supervisor_pid: Process.pid, instance_token: 'runtime-token')
    File.write(
      state_file,
      JSON.pretty_generate(
        {
          schema_version: 1,
          updated_at: Time.utc(2026, 4, 2, 12, 0, 0).iso8601,
          started_at: Time.utc(2026, 4, 2, 12, 0, 0).iso8601,
          instance_token:,
          control_socket_path: socket_file,
          supervisor_pid:,
          snapshot: {
            worker_id: 'worker-supervisor',
            supervisor_pid:,
            queues: ['billing'],
            configured_processes: 1,
            configured_threads: 1,
            phase:,
            child_processes: []
          }
        }
      )
    )
  end

  def with_control_server
    server = UNIXServer.new(socket_file)
    received_requests = Queue.new
    server_thread = Thread.new do
      client = server.accept
      received_requests << JSON.parse(client.read)
      client.write(JSON.generate('ok' => true))
      client.close
    ensure
      server.close
    end

    yield(received_requests)
  ensure
    server_thread&.join
    FileUtils.rm_f(socket_file)
  end

  it 'prints runtime inspection JSON from the state file' do
    write_state_file

    with_control_server do
      expect do
        described_class.start(['runtime', 'inspect', '--state-file', state_file], suppress_header: true)
      end.to output(/"schema_version": 1/).to_stdout
    end
  end

  it 'marks the runtime command as exit-on-failure' do
    expect(runtime_command_class.exit_on_failure?).to be(true)
  end

  it 'sends TERM to the recorded supervisor pid for drain' do
    write_state_file(supervisor_pid: 12_345)

    with_control_server do |received_requests|
      described_class.start(['runtime', 'drain', '--state-file', state_file], suppress_header: true)

      expect(received_requests.pop).to eq(
        'command' => 'drain',
        'instance_token' => 'runtime-token'
      )
    end
  end

  it 'sends KILL to the recorded supervisor pid for force-stop' do
    write_state_file(supervisor_pid: 12_345)

    with_control_server do |received_requests|
      described_class.start(['runtime', 'force-stop', '--state-file', state_file], suppress_header: true)

      expect(received_requests.pop).to eq(
        'command' => 'force_stop',
        'instance_token' => 'runtime-token'
      )
    end
  end

  it 'fails when the runtime state file is stale' do
    write_state_file(phase: 'running', supervisor_pid: 12_345)
    allow(Process).to receive(:kill).with(0, 12_345).and_raise(Errno::ESRCH)

    expect do
      described_class.start(['runtime', 'inspect', '--state-file', state_file], suppress_header: true)
    end.to output(/runtime state file is stale for pid 12345/).to_stderr.and raise_error(SystemExit)
  end

  it 'raises a Thor error directly from runtime command helpers for invalid state files' do
    command = runtime_command_class.allocate
    allow(command).to receive(:options).and_return({ state_file: state_file })

    expect { command.show }.to raise_error(Thor::Error, /does not exist/)
    expect { command.send(:send_control_command, 'drain') }.to raise_error(Thor::Error, /does not exist/)
  end

  it 'surfaces control socket failures as Thor errors' do
    write_state_file(supervisor_pid: 12_345)

    expect do
      described_class.start(['runtime', 'drain', '--state-file', state_file], suppress_header: true)
    end.to output(/runtime control socket is missing:/).to_stderr.and raise_error(SystemExit)
  end

  it 'raises a Thor error when the control server rejects the command' do
    write_state_file(supervisor_pid: 12_345)
    command = runtime_command_class.allocate
    allow(command).to receive(:options).and_return({ state_file: state_file })

    server = UNIXServer.new(socket_file)
    server_thread = Thread.new do
      client = server.accept
      client.read
      client.write(JSON.generate('error' => 'cannot drain now'))
      client.close
    ensure
      server.close
    end

    expect do
      command.send(:send_control_command, 'drain')
    end.to raise_error(Thor::Error, 'cannot drain now')
  ensure
    server_thread&.join
    FileUtils.rm_f(socket_file)
  end

  it 'raises a Thor error when the control server returns an unknown response shape' do
    write_state_file(supervisor_pid: 12_345)
    command = runtime_command_class.allocate
    allow(command).to receive(:options).and_return({ state_file: state_file })

    server = UNIXServer.new(socket_file)
    server_thread = Thread.new do
      client = server.accept
      client.read
      client.write(JSON.generate('status' => 'mystery'))
      client.close
    ensure
      server.close
    end

    expect do
      command.send(:send_control_command, 'drain')
    end.to raise_error(Thor::Error, 'unknown runtime control error')
  ensure
    server_thread&.join
    FileUtils.rm_f(socket_file)
  end

  it 'times out when the control server accepts the request but never responds' do
    write_state_file(supervisor_pid: 12_345)
    command = runtime_command_class.allocate
    allow(command).to receive(:options).and_return({ state_file: state_file })
    stub_const("#{runtime_command_class}::RESPONSE_TIMEOUT_SECONDS", 0)

    server = UNIXServer.new(socket_file)
    server_thread = Thread.new do
      client = server.accept
      client.read
      sleep(0.1)
      client.close
    ensure
      server.close
    end

    expect do
      command.send(:send_control_command, 'drain')
    end.to raise_error(Thor::Error, /timed out waiting for supervisor response/)
  ensure
    server_thread&.join
    FileUtils.rm_f(socket_file)
  end

  it 'wraps socket-level control failures in a Thor error when called directly' do
    write_state_file(supervisor_pid: 12_345)
    command = runtime_command_class.allocate
    allow(command).to receive(:options).and_return({ state_file: state_file })
    stale_server = UNIXServer.new(socket_file)
    stale_server.close

    expect do
      command.send(:send_control_command, 'drain')
    end.to raise_error(Thor::Error, /runtime control failed:/)
  ensure
    FileUtils.rm_f(socket_file)
  end

  it 'raises a Thor error when the control socket path points to a regular file' do
    write_state_file(supervisor_pid: 12_345)
    File.write(socket_file, 'not-a-socket')
    command = runtime_command_class.allocate
    allow(command).to receive(:options).and_return({ state_file: state_file })

    expect do
      command.send(:send_control_command, 'drain')
    end.to raise_error(Thor::Error, /not a Unix socket/)
  end
end
