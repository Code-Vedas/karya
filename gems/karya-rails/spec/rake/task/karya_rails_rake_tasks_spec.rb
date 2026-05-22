# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'rake'
require 'pathname'
require_relative '../../rails_helper'

RSpec.describe Rake::Task, '#karya_rails_rake_tasks' do
  let(:rake) { Rake::Application.new }

  around do |example|
    original_rake = Rake.application
    Rake.application = rake
    example.run
  ensure
    Rake.application = original_rake
  end

  before do
    described_class.clear
    described_class.define_task(:environment)
    allow(Rails).to receive(:root).and_return(Pathname('/tmp/app'))
    Karya::Rails::RakeTasks.load!
  end

  it 'installs framework files and migrations through the shared installer' do
    installer = ->(**) {}
    allow(Karya::Internal::FrameworkInstaller).to receive_messages(
      migration_kind: :sqlite,
      active_record_migration_installer: installer,
      install!: nil,
      install_migrations!: nil
    )

    described_class['karya:install:all'].invoke('sqlite')
    described_class['karya:install:migrations'].reenable
    described_class['karya:install:migrations'].invoke('sqlite')

    expect(Karya::Internal::FrameworkInstaller).to have_received(:install!).with(
      framework_class_name: 'Karya::Rails',
      root_path: '/tmp/app',
      backend: 'sqlite',
      migration_kind: :sqlite,
      migration_target_dir: '/tmp/app/db/migrate',
      migration_installer: installer
    )
    expect(Karya::Internal::FrameworkInstaller).to have_received(:install_migrations!).with(
      migration_kind: :sqlite,
      migration_target_dir: '/tmp/app/db/migrate',
      migration_installer: installer
    )
  end
end
