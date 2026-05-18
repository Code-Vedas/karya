# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Karya::Sequel do
  it 'writes a Sequel migration for the Postgres backend' do
    allow(Kernel).to receive(:require).and_call_original
    allow(Kernel).to receive(:require).with('sequel').and_return(true)

    Dir.mktmpdir('karya-sequel-migration-') do |dir|
      path = described_class.install_postgres_migration(target_dir: dir)
      contents = File.read(path)

      expect(File.basename(path)).to match(/\A\d{14}_create_karya_postgres_backend\.rb\z/)
      expect(contents).to include('Sequel.migration do')
      expect(contents).to include('create_table?(:karya_queue_store_states)')
    end
  end

  it 'falls back to the default migration name when the requested name is blank' do
    Dir.mktmpdir('karya-sequel-default-migration-') do |dir|
      path = described_class.install_postgres_migration(target_dir: dir, migration_name: '')

      expect(File.basename(path)).to match(/\A\d{14}_create_karya_postgres_backend\.rb\z/)
    end
  end

  it 'raises an actionable load error when sequel is unavailable' do
    allow(described_class).to receive(:require).with('sequel').and_raise(LoadError, 'cannot load such file -- sequel')

    expect do
      described_class.require_sequel!
    end.to raise_error(
      LoadError,
      /Add `gem 'sequel'` to your Gemfile to use Karya::Sequel Postgres migration support\./
    )
  end
end
