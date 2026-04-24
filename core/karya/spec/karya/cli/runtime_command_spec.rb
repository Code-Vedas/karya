# frozen_string_literal: true

RSpec.describe Karya::CLI::RuntimeCommand do
  subject(:command) { described_class.new([], { state_file: '/tmp/runtime-state.json' }, {}) }

  it 'prints the live runtime payload for show' do
    allow(Karya::WorkerSupervisor::RuntimeStateStore).to receive(:live_payload!).and_return({ 'ok' => true })

    expect { command.show }.to output("#{JSON.pretty_generate({ 'ok' => true })}\n").to_stdout
  end

  it 'maps invalid runtime state errors into thor errors' do
    allow(Karya::WorkerSupervisor::RuntimeStateStore).to receive(:live_payload!).and_raise(
      Karya::WorkerSupervisor::InvalidRuntimeStateFileError,
      'missing runtime state'
    )

    expect do
      command.show
    end.to raise_error(Thor::Error, 'missing runtime state')
  end
end
