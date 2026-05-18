# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'tmpdir'

RSpec.describe Karya::Hanami do
  it 'exposes the version' do
    expect(described_class::VERSION).to eq('0.1.0')
  end

  it 'delegates Postgres migration install through the folded Sequel support' do
    Dir.mktmpdir('karya-hanami-migration-') do |dir|
      path = described_class.install_postgres_migration(target_dir: dir)

      expect(File.basename(path)).to match(/\A\d{14}_create_karya_postgres_backend\.rb\z/)
      expect(File.read(path)).to include('create_table?(:karya_queue_store_states)')
    end
  end

  it 'renders the dashboard document for the Hanami mount path' do
    document = described_class.render_dashboard_page

    expect_dashboard_document(document, mount_path: '/karya', title: 'Karya Dashboard')
  end

  it 'builds a prefixed mount path' do
    expect(described_class.mount_path(prefix: 'admin')).to eq('/admin/karya')
  end

  it 'strips repeated slashes and falls back to the default mount path for blank scopes' do
    expect(described_class.mount_path(prefix: '//ops//')).to eq('/ops/karya')
    expect(described_class.mount_path(prefix: '///')).to eq('/karya')
  end
end
