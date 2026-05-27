# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::FrameworkInstaller do
  it 'creates bootstrap files and installs migrations' do
    Dir.mktmpdir('framework-installer-') do |root|
      migration_calls = []
      described_class.install!(
        framework_class_name: 'Karya::Rails',
        root_path: root,
        backend: 'postgres',
        migration_kind: :postgres,
        migration_target_dir: File.join(root, 'db', 'migrate'),
        migration_installer: ->(**options) { migration_calls << options }
      )

      expect(File.read(File.join(root, 'config', 'karya.yml'))).to include('backend: postgres')
      expect(File.read(File.join(root, 'app', 'jobs', 'application_job.rb'))).to include('class ApplicationJob < Karya::Rails::Job')
      expect(File.read(File.join(root, 'app', 'workflows', 'application_workflows.rb'))).to include('extend Karya::Rails::Workflow::Source')
      expect(migration_calls).to eq([{ target_dir: File.join(root, 'db', 'migrate'), migration_name: 'create_karya_postgres_backend' }])
    end
  end

  it 'maps backend installers and validates backend names' do
    allow(Karya::ActiveRecord).to receive(:install_mysql_migration)
    allow(Karya::ActiveRecord).to receive(:install_sqlite_migration)
    allow(Karya::Sequel).to receive(:install_mysql_migration)
    allow(Karya::Sequel).to receive(:install_sqlite_migration)

    expect(described_class.migration_kind('mysql')).to eq(:mysql)
    expect(described_class.migration_kind('sqlite')).to eq(:sqlite)
    expect { described_class.migration_kind('bogus') }.to raise_error(ArgumentError, /unsupported backend/)
    described_class.active_record_migration_installer(:mysql).call(target_dir: '/tmp', migration_name: 'mysql')
    described_class.active_record_migration_installer(:sqlite).call(target_dir: '/tmp', migration_name: 'sqlite')
    expect(described_class.active_record_migration_installer(:mysql)).to respond_to(:call)
    expect(described_class.sequel_migration_installer(:postgres)).to respond_to(:call)
    described_class.sequel_migration_installer(:mysql).call(target_dir: '/tmp', migration_name: 'mysql')
    described_class.sequel_migration_installer(:sqlite).call(target_dir: '/tmp', migration_name: 'sqlite')
    expect(described_class.backend_class_name('sqlite')).to eq('SQLite')
    expect(described_class.backend_class_name('mysql')).to eq('MySQL')
    expect { described_class.backend_class_name('bogus') }.to raise_error(ArgumentError, /unsupported backend/)
  end

  it 'does not overwrite existing generated files' do
    Dir.mktmpdir('framework-installer-existing-') do |root|
      path = File.join(root, 'config', 'karya.yml')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, 'existing')

      described_class.create_runtime_config(root_path: root, backend: 'postgres')

      expect(File.read(path)).to eq('existing')
    end
  end

  it 'creates the legacy initializer path through the runtime config generator' do
    Dir.mktmpdir('framework-installer-initializer-') do |root|
      described_class.create_initializer(root_path: root, backend: 'sqlite')

      expect(File.read(File.join(root, 'config', 'karya.yml'))).to include('backend: sqlite')
    end
  end
end
