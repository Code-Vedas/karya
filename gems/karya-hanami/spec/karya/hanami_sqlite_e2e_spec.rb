# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'

RSpec.describe Karya::Hanami, :dashboard_manifest_fixture, :integration do
  if ENV['E2E'] == '1'
    require 'rack/test'
    require 'sequel'
    require 'sequel/extensions/migration'
    include Rack::Test::Methods
  end

  around do |example|
    skip 'set E2E=1 for SQLite e2e coverage' unless ENV['E2E'] == '1'

    KaryaHanamiDummyAppSupport.with_dummy_app do |_app_root, rack_app|
      self.current_rack_app = rack_app
      with_sqlite_backend(prefix: 'karya_hanami_sqlite_e2e', namespace: 'hanami_sqlite_e2e') do |database_url|
        Dir.mktmpdir('karya-hanami-sqlite-migrations-') do |migration_dir|
          described_class.install_sqlite_migration(target_dir: migration_dir)
          db = Sequel.connect(sequel_database_url_for(database_url))
          Sequel::Migrator.run(db, migration_dir)
          example.run
        ensure
          db&.disconnect
        end
      end
    end
  ensure
    self.current_rack_app = nil
  end

  def app
    current_rack_app
  end

  it 'serves the packaged dashboard document' do
    get '/karya'

    expect(last_response.status).to eq(200)
    expect_dashboard_document(last_response.body, mount_path: '/karya', title: 'Karya Dashboard')
  end

  it 'uses the configured SQLite backend through the Hanami host route' do
    get '/karya/runtime-probe'

    expect(last_response.status).to eq(200)
    payload = JSON.parse(last_response.body)
    expect(payload.fetch('backend')).to eq('sqlite')
    expect(payload.fetch('job_id')).to start_with('hanami-probe-')
  end
end
