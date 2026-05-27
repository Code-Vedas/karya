# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::FrameworkRuntimeControl do
  let(:socket) do
    instance_double(
      UNIXSocket,
      write: nil,
      close_write: nil,
      readpartial: '{"ok":true}',
      wait_readable: true
    )
  end

  before do
    read_count = 0
    allow(socket).to receive(:readpartial) do
      read_count += 1
      raise EOFError if read_count > 1

      '{"ok":true}'
    end
  end

  it 'delegates inspect and sends runtime control commands' do
    allow(Karya::WorkerSupervisor::RuntimeStateStore).to receive_messages(
      live_payload!: { 'state' => 'running' },
      control_payload!: {
        'control_socket_path' => '/tmp/karya.sock',
        'instance_token' => 'token'
      }
    )
    allow(UNIXSocket).to receive(:open).and_yield(socket)
    allow(JSON).to receive(:parse).and_return({ 'ok' => true })

    expect(described_class.inspect(state_file: 'tmp/state.json')).to eq('state' => 'running')
    expect(described_class.drain(state_file: 'tmp/state.json')).to eq('ok' => true)
    expect(described_class.force_stop(state_file: 'tmp/state.json')).to eq('ok' => true)
  end

  it 'wraps runtime control failures' do
    allow(Karya::WorkerSupervisor::RuntimeStateStore).to receive(:control_payload!).and_raise(KeyError)

    expect do
      described_class.drain(state_file: 'tmp/state.json')
    end.to raise_error(Karya::WorkerSupervisor::RuntimeControlUnavailableError)
  end

  it 'raises for error responses and timeouts' do
    allow(Karya::WorkerSupervisor::RuntimeStateStore).to receive(:control_payload!).and_return(
      'control_socket_path' => '/tmp/karya.sock',
      'instance_token' => 'token'
    )
    allow(UNIXSocket).to receive(:open).and_yield(socket)
    allow(JSON).to receive(:parse).and_return({ 'ok' => false, 'error' => 'denied' })

    expect do
      described_class.force_stop(state_file: 'tmp/state.json')
    end.to raise_error(Karya::WorkerSupervisor::RuntimeControlUnavailableError, /denied/)

    allow(socket).to receive(:wait_readable).and_return(nil)
    expect do
      described_class.send(:wait_for_response, socket)
    end.to raise_error(Karya::WorkerSupervisor::RuntimeControlUnavailableError, /timed out/)
  end

  it 'raises when the supervisor response exceeds the byte limit' do
    large_chunk = 'x' * described_class::MAX_RESPONSE_BYTES
    allow(socket).to receive(:readpartial).and_return(large_chunk, 'y')

    expect do
      described_class.send(:read_response, socket)
    end.to raise_error(Karya::WorkerSupervisor::RuntimeControlUnavailableError, /exceeded/)
  end

  it 'skips empty socket chunks while reading a response' do
    read_count = 0
    allow(socket).to receive(:readpartial) do
      read_count += 1

      case read_count
      when 1 then ''
      when 2 then '{"ok":true}'
      else raise EOFError
      end
    end

    expect(described_class.send(:read_response, socket)).to eq('{"ok":true}')
  end
end
