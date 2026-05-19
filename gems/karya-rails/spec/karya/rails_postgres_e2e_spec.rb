# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'securerandom'
require 'tmpdir'

RSpec.describe Karya::Rails, :dashboard_manifest_fixture, :integration do
  if ENV['E2E'] == '1'
    require 'rails_helper'
    require 'rack/test'
    include Rack::Test::Methods
  end

  around do |example|
    with_postgres_backend(prefix: 'karya_rails_e2e', namespace: 'rails_e2e') do |database_url|
      Dir.mktmpdir('karya-rails-migrations-') do |migration_dir|
        migration_name = "Create Karya Postgres Backend #{SecureRandom.hex(4)}"
        migration_path = described_class.install_postgres_migration(target_dir: migration_dir, migration_name:)
        migration_class_name = Karya::ActiveRecord.normalize_migration_name(migration_name)
        ActiveRecord::Base.establish_connection(database_url)
        ActiveRecord::Migration.verbose = false
        load migration_path
        Object.const_get(migration_class_name).migrate(:up)
        Karya.configure_backend(Karya::Backend::Postgres, url: database_url, namespace: 'rails_e2e')
        example.run
      ensure
        ActiveRecord::Base.connection_pool.disconnect!
      end
    end
  end

  it 'mounts the dashboard engine and serves the packaged document' do
    get '/karya'

    expect(last_response).to have_http_status(:ok)
    expect_dashboard_document(last_response.body, mount_path: '/karya', title: 'Karya Dashboard')
  end

  it 'uses the configured Postgres backend through the mounted engine' do
    get '/karya/runtime-probe'

    expect(last_response).to have_http_status(:ok)
    payload = JSON.parse(last_response.body)
    expect(payload.fetch('backend')).to eq('postgres')
    expect(payload.fetch('job_id')).to start_with('rails-probe-')
    expect(payload.fetch('mount_path')).to eq('/karya')
  end

  def app
    Rails.application
  end
end
