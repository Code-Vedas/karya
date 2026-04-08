# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'socket'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'Karya::WorkerSupervisor::RuntimeControlServer' do
  let(:described_class) { Karya::WorkerSupervisor.const_get(:RuntimeControlServer, false) }
  let(:logger) { instance_double(Karya::Internal::NullLogger, error: nil) }
  let(:state_dir) { Dir.mktmpdir('kr', '/tmp') }
  let(:socket_path) { File.join(state_dir, 'runtime.sock') }
  let(:commands) { [] }
  let(:server) do
    described_class.new(
      path: socket_path,
      instance_token: 'runtime-token',
      command_handler: ->(command) { commands << command },
      logger:
    )
  end

  after do
    server.stop if File.exist?(socket_path)
    FileUtils.rm_rf(state_dir)
  end

  def socket_request(payload)
    UNIXSocket.open(socket_path) do |socket|
      socket.write(JSON.generate(payload))
      socket.close_write
      JSON.parse(socket.read)
    end
  end

  it 'starts, serves valid requests, and removes the socket on stop' do
    server.start

    expect(socket_request('command' => 'drain', 'instance_token' => 'runtime-token')).to eq('ok' => true)
    expect(commands).to eq(['drain'])

    server.stop

    expect(File.exist?(socket_path)).to be(false)
  end

  it 'accepts ping requests without dispatching to the command handler' do
    server.start

    expect(socket_request('command' => 'ping', 'instance_token' => 'runtime-token')).to eq('ok' => true)
    expect(commands).to eq([])
  end

  it 'creates the socket parent directory before binding' do
    nested_socket_path = File.join(state_dir, 'nested', 'runtime.sock')
    nested_server = described_class.new(
      path: nested_socket_path,
      instance_token: 'runtime-token',
      command_handler: ->(command) { commands << command },
      logger:
    )

    nested_server.start

    expect(File.exist?(nested_socket_path)).to be(true)
  ensure
    nested_server&.stop
  end

  it 'rejects startup when the socket path is occupied by a regular file' do
    File.write(socket_path, 'occupied')

    expect do
      server.start
    end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /occupied by a non-socket file/)
    expect(File.read(socket_path)).to eq('occupied')
  end

  it 'replaces a stale socket file before binding a fresh control server' do
    stale_server = UNIXServer.new(socket_path)
    stale_server.close

    expect { server.start }.not_to raise_error
    expect(File.socket?(socket_path)).to be(true)
  ensure
    server.stop if File.socket?(socket_path)
  end

  it 'can stop safely before the server has started' do
    expect { server.stop }.not_to raise_error
  end

  it 'returns an invalid-request error for malformed JSON payloads' do
    response = server.send(:control_response_for, '{')

    expect(response.fetch('error')).to match(/invalid control request/)
  end

  it 'returns an invalid-request error for non-object JSON payloads' do
    response = server.send(:control_response_for, JSON.generate(['drain']))

    expect(response.fetch('error')).to match(/invalid control request: runtime control request must be a JSON object/)
  end

  it 'returns a runtime error when the control token does not match' do
    response = server.send(:control_response_for, JSON.generate('command' => 'drain', 'instance_token' => 'wrong-token'))

    expect(response).to eq('error' => 'runtime control token does not match the running supervisor')
  end

  it 'returns handled runtime-control errors from the command handler' do
    unavailable_error = Karya::WorkerSupervisor::RuntimeControlUnavailableError.new('worker supervisor is not running')
    unavailable_server = described_class.new(
      path: socket_path,
      instance_token: 'runtime-token',
      command_handler: ->(_command) { raise unavailable_error },
      logger:
    )

    response = unavailable_server.send(:control_response_for, JSON.generate('command' => 'drain', 'instance_token' => 'runtime-token'))

    expect(response).to eq('error' => 'worker supervisor is not running')
  end

  it 're-raises unhandled command errors' do
    expect do
      described_class::ErrorResponse.new(error: RuntimeError.new('boom')).to_h
    end.to raise_error(RuntimeError, 'boom')
  end

  it 'logs run-loop failures and closes accepted clients' do
    client = instance_double(IO, write: nil, close: nil, wait_readable: nil)
    read_count = 0
    allow(client).to receive(:readpartial) do
      read_count += 1
      raise EOFError if read_count > 1

      JSON.generate('command' => 'drain', 'instance_token' => 'runtime-token')
    end
    fake_server = instance_double(UNIXServer)
    accept_count = 0
    allow(fake_server).to receive(:accept) do
      accept_count += 1
      if accept_count == 1
        client
      elsif accept_count == 2
        raise 'boom'
      else
        raise IOError
      end
    end

    server.instance_variable_set(:@server, fake_server)
    server.instance_variable_set(:@stopping, true)

    server.send(:run_loop)

    expect(client).to have_received(:close)
    expect(logger).to have_received(:error).with(
      'runtime control server failed',
      error_class: 'RuntimeError',
      error_message: 'boom',
      socket_path:
    )
  end

  it 'does not try to close the previous iteration client again when the next accept fails early' do
    previous_client = instance_double(IO)
    fake_server = instance_double(UNIXServer)
    accept_count = 0
    allow(fake_server).to receive(:accept) do
      accept_count += 1
      accept_count == 1 ? previous_client : raise(IOError)
    end
    allow(previous_client).to receive(:close)
    server.instance_variable_set(:@server, fake_server)
    server.instance_variable_set(:@stopping, true)
    allow(server).to receive(:handle_client)

    expect { server.send(:run_loop) }.not_to raise_error
    expect(previous_client).to have_received(:close).once
  end

  it 're-raises server IO errors when shutdown has not started' do
    fake_server = instance_double(UNIXServer)
    allow(fake_server).to receive(:accept).and_raise(IOError)
    server.instance_variable_set(:@server, fake_server)
    server.instance_variable_set(:@stopping, false)

    expect do
      server.send(:run_loop)
    end.to raise_error(IOError)
  end

  it 'returns a timeout error when a client never finishes writing the request' do
    client = instance_double(IO, write: nil, close: nil, wait_readable: nil)
    session = described_class::ClientSession.new(client:, response_builder: ->(_raw_request) { { 'ok' => true } })

    expect do
      session.call
    end.to raise_error(Karya::WorkerSupervisor::InvalidRuntimeStateFileError, /timed out while reading/)
  end

  it 'rejects requests that exceed the maximum payload size' do
    client = instance_double(IO, write: nil, close: nil)
    allow(client).to receive_messages(
      wait_readable: client,
      readpartial: 'x' * (described_class::MAX_REQUEST_BYTES + 1)
    )
    session = described_class::ClientSession.new(client:, response_builder: ->(_raw_request) { { 'ok' => true } })
    oversize_request_error = /exceeds #{described_class::MAX_REQUEST_BYTES} bytes/o

    expect do
      session.call
    end.to raise_error(Karya::WorkerSupervisor::InvalidRuntimeStateFileError, oversize_request_error)
  end

  it 'finishes a request when the client closes after sending data' do
    client = instance_double(IO, write: nil, close: nil)
    allow(client).to receive(:wait_readable).and_return(client, client)
    read_count = 0
    allow(client).to receive(:readpartial) do
      read_count += 1
      raise EOFError if read_count > 1

      '{"command":"drain","instance_token":"runtime-token"}'
    end
    session = described_class::ClientSession.new(client:, response_builder: ->(_raw_request) { { 'ok' => true } })

    expect { session.call }.not_to raise_error
    expect(client).to have_received(:write).with(JSON.generate('ok' => true))
  end

  it 'kills the server thread if it does not stop within the join timeout' do
    server_thread = instance_double(Thread, join: nil, kill: nil)
    server.instance_variable_set(:@server_thread, server_thread)

    server.send(:stop_server_thread)

    expect(server_thread).to have_received(:join).with(described_class::STOP_TIMEOUT_SECONDS)
    expect(server_thread).to have_received(:kill)
    expect(server_thread).to have_received(:join).twice
  end
end
