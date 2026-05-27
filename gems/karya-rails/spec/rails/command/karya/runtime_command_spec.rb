# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../../rails_helper'
require 'rails/commands/karya/runtime/runtime_command'

RSpec.describe Rails::Command::Karya::RuntimeCommand do
  let(:command) { described_class.allocate }

  before do
    allow(command).to receive(:boot_application!)
    allow(command).to receive(:options).and_return({ name: 'billing-worker' })
    allow(command).to receive(:say)
  end

  it 'dispatches inspect, drain, and force_stop through the Rails runtime wrapper' do
    allow(Karya::Rails).to receive_messages(
      runtime_inspect: { 'state' => 'running' },
      runtime_drain: { 'ok' => true },
      runtime_force_stop: { 'ok' => true }
    )

    command.inspect('billing')
    command.drain('billing')
    command.force_stop('billing')

    expect(Karya::Rails).to have_received(:runtime_inspect).with(queues: ['billing'], name: 'billing-worker')
    expect(Karya::Rails).to have_received(:runtime_drain).with(queues: ['billing'], name: 'billing-worker')
    expect(Karya::Rails).to have_received(:runtime_force_stop).with(queues: ['billing'], name: 'billing-worker')
  end

  it 'rejects empty queue lists' do
    expect { command.inspect }.to raise_error(Thor::Error, /at least one queue is required/)
  end
end
