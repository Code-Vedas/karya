# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Rails, :dashboard_manifest_fixture do
  it 'exposes the version' do
    expect(described_class::VERSION).to eq('0.1.0')
  end

  it 'delegates Postgres migration install through the folded Active Record support' do
    Dir.mktmpdir('karya-rails-migration-') do |dir|
      path = described_class.install_postgres_migration(target_dir: dir)

      expect(File.basename(path)).to match(/\A\d{14}_create_karya_postgres_backend\.rb\z/)
      expect(File.read(path)).to include('create_table :karya_queue_store_states')
    end
  end

  it 'delegates MySQL migration install through the folded Active Record support' do
    Dir.mktmpdir('karya-rails-mysql-migration-') do |dir|
      path = described_class.install_mysql_migration(target_dir: dir)

      expect(File.basename(path)).to match(/\A\d{14}_create_karya_mysql_backend\.rb\z/)
      expect(File.read(path)).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_states')
    end
  end

  it 'renders the dashboard document for the mounted Rails path' do
    document = described_class.render_dashboard_page

    expect_dashboard_document(document, mount_path: '/karya', title: 'Karya Dashboard')
  end

  it 'builds a scoped mount path when scope is provided' do
    document = described_class.render_dashboard_page(scope: '//ops//')

    expect_dashboard_document(document, mount_path: '/ops/karya', title: 'Karya Dashboard')
  end

  it 'rejects combining scope and mount_path' do
    expect do
      described_class.render_dashboard_page(scope: 'ops', mount_path: '/custom/karya')
    end.to raise_error(ArgumentError, 'scope and mount_path cannot be combined')
  end
end
