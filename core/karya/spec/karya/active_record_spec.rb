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

  it 'raises an actionable load error when active_record is unavailable' do
    allow(described_class).to receive(:require).with('active_record').and_raise(LoadError, 'cannot load such file -- active_record')

    expect do
      described_class.require_activerecord!
    end.to raise_error(
      LoadError,
      /Add `gem 'activerecord'` to your Gemfile to use Karya::ActiveRecord Postgres migration support\./
    )
  end
end
