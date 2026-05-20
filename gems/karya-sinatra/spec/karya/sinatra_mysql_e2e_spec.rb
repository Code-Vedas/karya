# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'fileutils'
require 'tmpdir'

RSpec.describe Karya::Sinatra, :dashboard_manifest_fixture, :integration do
  if ENV['E2E'] == '1'
    require 'rack'
    require 'rack/test'
    require 'sequel'
    require 'sequel/extensions/migration'
    include Rack::Test::Methods
  end

  def with_dummy_app(source_dir)
    Dir.mktmpdir('karya-sinatra-') do |root|
      app_root = File.join(root, 'app')
      FileUtils.copy_entry(source_dir, app_root)
      app, = Rack::Builder.parse_file(File.join(app_root, 'config.ru'))
      yield app
    end
  end

  around do |example|
    skip 'set MYSQL_DATABASE_URL for MySQL e2e coverage' unless ENV['MYSQL_DATABASE_URL']

    source_dir = File.expand_path('../dummy/modular', __dir__)
    with_dummy_app(source_dir) do |rack_app|
      self.current_rack_app = rack_app
      with_mysql_backend(prefix: 'karya_sinatra_mysql_e2e', namespace: 'sinatra_mysql_e2e') do |database_url|
        Dir.mktmpdir('karya-sinatra-mysql-migrations-') do |migration_dir|
          described_class.install_mysql_migration(target_dir: migration_dir)
          db = Sequel.connect(database_url)
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
    get '/karya', {}, { 'HTTP_HOST' => 'localhost' }

    expect(last_response.status).to eq(200)
    expect_dashboard_document(last_response.body, mount_path: '/karya', title: 'Karya Dashboard')
  end

  it 'uses the configured MySQL backend through the Sinatra host route' do
    get '/karya/runtime-probe', {}, { 'HTTP_HOST' => 'localhost' }

    expect(last_response.status).to eq(200)
    payload = JSON.parse(last_response.body)
    expect(payload.fetch('backend')).to eq('mysql')
    expect(payload.fetch('job_id')).to start_with('sinatra-modular-probe-')
  end
end
