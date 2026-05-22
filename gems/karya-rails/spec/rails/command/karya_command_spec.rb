# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../rails_helper'
require 'rails/commands/karya/karya_command'

RSpec.describe Rails::Command::KaryaCommand do
  it 'dispatches work through the Rails worker wrapper' do
    command = described_class.allocate
    allow(command).to receive(:boot_application!)
    allow(command).to receive(:options).and_return({ include_active_job: false, processes: 2 })
    allow(Karya::Rails.support).to receive(:run_worker).and_return(:ok)

    command.work('billing')

    expect(Karya::Rails.support).to have_received(:run_worker).with(
      queues: ['billing'],
      name: nil,
      extra_handlers: {},
      eager_load: kind_of(Proc),
      processes: 2
    )
  end

  it 'includes the ActiveJob bridge handler when requested' do
    command = described_class.allocate
    allow(command).to receive(:boot_application!)
    allow(command).to receive(:options).and_return({ include_active_job: true, processes: 2 })
    allow(Karya::Rails).to receive(:active_job_handler).and_return(:handler)
    allow(Rails.application).to receive(:eager_load!)
    allow(Karya::Rails.support).to receive(:run_worker) do |**kwargs|
      expect(kwargs.fetch(:eager_load)).to be_a(Proc)
      kwargs.fetch(:eager_load).call
      :ok
    end

    command.work('billing')

    expect(Rails.application).to have_received(:eager_load!)
    expect(Karya::Rails.support).to have_received(:run_worker)
  end

  it 'rejects missing queues' do
    command = described_class.allocate

    expect do
      command.work
    end.to raise_error(Thor::Error, /at least one queue is required/)
  end
end
