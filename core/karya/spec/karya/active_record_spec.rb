# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Karya::ActiveRecord do
  it 'writes an Active Record migration for the Postgres backend' do
    Dir.mktmpdir('karya-ar-migration-') do |dir|
      path = described_class.install_postgres_migration(target_dir: dir)
      contents = File.read(path)

      expect(File.basename(path)).to match(/\A\d{14}_create_karya_postgres_backend\.rb\z/)
      expect(contents).to include("class CreateKaryaPostgresBackend < ActiveRecord::Migration[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]")
      expect(contents).to include('create_table :karya_queue_store_states')
    end
  end

  it 'falls back to the default migration name when the requested name is blank' do
    Dir.mktmpdir('karya-ar-migration-default-') do |dir|
      path = described_class.install_postgres_migration(target_dir: dir, migration_name: '')

      expect(File.basename(path)).to match(/\A\d{14}_create_karya_postgres_backend\.rb\z/)
    end
  end

  it 'writes an Active Record migration for the MySQL backend' do
    Dir.mktmpdir('karya-ar-mysql-migration-') do |dir|
      path = described_class.install_mysql_migration(target_dir: dir)
      contents = File.read(path)

      expect(File.basename(path)).to match(/\A\d{14}_create_karya_mysql_backend\.rb\z/)
      expect(contents).to include("class CreateKaryaMysqlBackend < ActiveRecord::Migration[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]")
      expect(contents).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_states')
      expect(contents).to include('payload longtext NOT NULL')
    end
  end

  it 'falls back to the default MySQL migration name when the requested name is blank' do
    Dir.mktmpdir('karya-ar-mysql-migration-default-') do |dir|
      path = described_class.install_mysql_migration(target_dir: dir, migration_name: '')

      expect(File.basename(path)).to match(/\A\d{14}_create_karya_my_sql_backend\.rb\z/)
    end
  end

  it 'normalizes punctuation-heavy migration names into Rails class and file names' do
    expect(described_class.normalize_migration_name('create karya/API v2 backend')).to eq('CreateKaryaApiV2Backend')
    expect(described_class.normalize_migration_name('create!! karya')).to eq('CreateKarya')
    expect(described_class.underscore('CreateKaryaAPIBackend')).to eq('create_karya_api_backend')
  end

  it 'raises an actionable load error when active_record is unavailable' do
    allow(described_class).to receive(:require).with('active_record').and_raise(LoadError, 'cannot load such file -- active_record')

    expect do
      described_class.require_activerecord!
    end.to raise_error(
      LoadError,
      /Add `gem 'activerecord'` to your Gemfile to use Karya::ActiveRecord SQL migration support\./
    )
  end

  it 'loads ActiveSupport inflector before calling underscore' do
    allow(described_class).to receive(:require_activerecord!).and_call_original

    expect(described_class.underscore('CreateKaryaAPIBackend')).to eq('create_karya_api_backend')
    expect(described_class).to have_received(:require_activerecord!)
  end
end
