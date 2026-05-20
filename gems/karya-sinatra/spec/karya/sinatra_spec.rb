# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'tmpdir'

RSpec.describe Karya::Sinatra, :dashboard_manifest_fixture do
  it 'exposes the version' do
    expect(described_class::VERSION).to eq('0.1.0')
  end

  it 'delegates Postgres migration install through the folded Sequel support' do
    Dir.mktmpdir('karya-sinatra-migration-') do |dir|
      path = described_class.install_postgres_migration(target_dir: dir)

      expect(File.basename(path)).to match(/\A\d{14}_create_karya_postgres_backend\.rb\z/)
      expect(File.read(path)).to include('create_table?(:karya_queue_store_states)')
    end
  end

  it 'delegates MySQL migration install through the folded Sequel support' do
    Dir.mktmpdir('karya-sinatra-mysql-migration-') do |dir|
      path = described_class.install_mysql_migration(target_dir: dir)

      expect(File.basename(path)).to match(/\A\d{14}_create_karya_mysql_backend\.rb\z/)
      expect(File.read(path)).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_states')
    end
  end

  it 'delegates SQLite migration install through the folded Sequel support' do
    Dir.mktmpdir('karya-sinatra-sqlite-migration-') do |dir|
      path = described_class.install_sqlite_migration(target_dir: dir)

      expect(File.basename(path)).to match(/\A\d{14}_create_karya_sqlite_backend\.rb\z/)
      expect(File.read(path)).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_states')
    end
  end

  it 'renders the dashboard document for the Sinatra mount path' do
    document = described_class.render_dashboard_page

    expect_dashboard_document(document, mount_path: '/karya', title: 'Karya Dashboard')
  end

  it 'builds a scoped mount path' do
    expect(described_class.mount_path(scope: 'ops')).to eq('/ops/karya')
  end

  it 'strips repeated slashes and falls back to the default mount path for blank scopes' do
    expect(described_class.mount_path(scope: '//ops//')).to eq('/ops/karya')
    expect(described_class.mount_path(scope: '///')).to eq('/karya')
  end
end
