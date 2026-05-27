# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::CLI::RuntimeCommand do
  subject(:command) { described_class.new([], { state_file: '/tmp/runtime-state.json' }, {}) }

  it 'prints the live runtime payload for show' do
    allow(Karya::Internal::FrameworkRuntimeControl).to receive(:inspect).and_return({ 'ok' => true })

    expect { command.show }.to output("#{JSON.pretty_generate({ 'ok' => true })}\n").to_stdout
  end

  it 'maps invalid runtime state errors into thor errors' do
    allow(Karya::Internal::FrameworkRuntimeControl).to receive(:inspect).and_raise(
      Karya::WorkerSupervisor::InvalidRuntimeStateFileError,
      'missing runtime state'
    )

    expect do
      command.show
    end.to raise_error(Thor::Error, 'missing runtime state')
  end

  it 'prefixes runtime control transport errors for control commands' do
    allow(Karya::Internal::FrameworkRuntimeControl).to receive(:drain).and_raise(
      Karya::WorkerSupervisor::RuntimeControlUnavailableError,
      'socket closed'
    )

    expect do
      command.drain
    end.to raise_error(Thor::Error, 'runtime control failed: socket closed')
  end

  it 'prefixes runtime control transport errors for force_stop' do
    allow(Karya::Internal::FrameworkRuntimeControl).to receive(:force_stop).and_raise(
      Karya::WorkerSupervisor::RuntimeControlUnavailableError,
      'permission denied'
    )

    expect do
      command.force_stop
    end.to raise_error(Thor::Error, 'runtime control failed: permission denied')
  end
end
