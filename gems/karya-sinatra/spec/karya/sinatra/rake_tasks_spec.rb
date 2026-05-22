# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'rake'

RSpec.describe Karya::Sinatra::RakeTasks do
  let(:rake) { Rake::Application.new }

  around do |example|
    original_rake = Rake.application
    Rake.application = rake
    described_class.instance_variable_set(:@loaded_applications, nil)
    example.run
  ensure
    described_class.instance_variable_set(:@loaded_applications, nil)
    Rake.application = original_rake
  end

  before do
    described_class.load!
  end

  it 'registers and dispatches runtime and install tasks' do
    allow(Karya::Sinatra).to receive_messages(
      runtime_inspect: { 'state' => 'running' },
      runtime_drain: { 'ok' => true },
      runtime_force_stop: { 'ok' => true }
    )
    allow(Karya::Internal::FrameworkInstaller).to receive_messages(
      migration_kind: :sqlite,
      sequel_migration_installer: ->(**) {},
      install!: nil,
      install_migrations!: nil
    )
    allow(JSON).to receive(:pretty_generate).and_return('{}')
    allow(described_class).to receive(:puts)

    Rake::Task['karya:runtime:inspect'].invoke('billing')
    Rake::Task['karya:runtime:drain'].invoke('billing')
    Rake::Task['karya:runtime:force_stop'].invoke('billing')
    Rake::Task['karya:install:all'].invoke('sqlite')
    Rake::Task['karya:install:migrations'].invoke('sqlite')

    expect(Karya::Sinatra).to have_received(:runtime_inspect).with(queues: ['billing'], name: nil)
    expect(Karya::Sinatra).to have_received(:runtime_drain).with(queues: ['billing'], name: nil)
    expect(Karya::Sinatra).to have_received(:runtime_force_stop).with(queues: ['billing'], name: nil)
    expect(Karya::Internal::FrameworkInstaller).to have_received(:install!)
    expect(Karya::Internal::FrameworkInstaller).to have_received(:install_migrations!)
    expect(described_class).to have_received(:puts).with('{}')
  end

  it 'does not re-register tasks once they are loaded' do
    allow(described_class).to receive(:register_work_task)

    described_class.load!

    expect(described_class).not_to have_received(:register_work_task)
  end
end
