# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'json'

RSpec.describe Karya::Hanami::CLI::Runtime do
  let(:framework) { class_double(Karya::Hanami) }
  let(:command) { described_class.new }

  before do
    allow(command).to receive(:framework).and_return(framework)
    allow(JSON).to receive(:pretty_generate).and_return('{}')
    allow(command).to receive(:puts)
    allow(framework).to receive(:load_config_file!).and_return(:ok)
  end

  it 'dispatches inspect, drain, and force-stop actions' do
    allow(framework).to receive_messages(
      runtime_inspect: { 'state' => 'running' },
      runtime_drain: :ok,
      runtime_force_stop: { 'ok' => true }
    )

    command.call(action: 'inspect', queues: 'billing', name: 'worker')
    command.call(action: 'drain', queues: 'billing', name: 'worker')
    command.call(action: 'force-stop', queues: 'billing', name: 'worker')

    expect(framework).to have_received(:runtime_inspect).with(queues: ['billing'], name: 'worker')
    expect(framework).to have_received(:runtime_drain).with(queues: ['billing'], name: 'worker')
    expect(framework).to have_received(:runtime_force_stop).with(queues: ['billing'], name: 'worker')
    expect(command).to have_received(:puts).with('{}').twice
  end

  it 'rejects unsupported actions' do
    expect do
      command.call(action: 'unknown', queues: 'billing')
    end.to raise_error(ArgumentError, /unsupported runtime action/)
  end

  it 'uses the Hanami framework module through the private accessor' do
    expect(described_class.new.send(:framework)).to eq(Karya::Hanami)
  end
end
