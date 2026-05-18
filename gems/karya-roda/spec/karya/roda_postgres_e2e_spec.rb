# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'

RSpec.describe Karya::Roda, :integration do
  if ENV['E2E'] == '1'
    require 'rack/test'
    require 'sequel'
    require 'sequel/extensions/migration'
    include Rack::Test::Methods
  end

  around do |example|
    original_backend_class = :__undefined__
    original_backend_options = :__undefined__
    original_backend_class = Karya.instance_variable_get(:@backend_class) if Karya.instance_variable_defined?(:@backend_class)
    original_backend_options = Karya.instance_variable_get(:@backend_options) if Karya.instance_variable_defined?(:@backend_options)

    KaryaRodaDummyAppSupport.with_dummy_app do |_app_root, rack_app|
      self.current_rack_app = rack_app
      with_postgres_database(prefix: 'karya_roda_e2e') do |database_url|
        Dir.mktmpdir('karya-roda-migrations-') do |migration_dir|
          described_class.install_postgres_migration(target_dir: migration_dir)
          db = Sequel.connect(database_url)
          Sequel::Migrator.run(db, migration_dir)
          Karya.configure_backend(Karya::Backend::Postgres, url: database_url, namespace: 'roda_e2e')
          example.run
        ensure
          db&.disconnect
        end
      end
    end
  ensure
    self.current_rack_app = nil
    if original_backend_class == :__undefined__
      Karya.remove_instance_variable(:@backend_class) if Karya.instance_variable_defined?(:@backend_class)
    else
      Karya.instance_variable_set(:@backend_class, original_backend_class)
    end

    if original_backend_options == :__undefined__
      Karya.remove_instance_variable(:@backend_options) if Karya.instance_variable_defined?(:@backend_options)
    else
      Karya.instance_variable_set(:@backend_options, original_backend_options)
    end
  end

  def app
    current_rack_app
  end

  it 'serves the packaged dashboard document' do
    get '/karya'

    expect(last_response.status).to eq(200)
    expect_dashboard_document(last_response.body, mount_path: '/karya', title: 'Karya Dashboard')
  end

  it 'uses the configured Postgres backend through the Roda host route' do
    get '/karya/runtime-probe'

    expect(last_response.status).to eq(200)
    payload = JSON.parse(last_response.body)
    expect(payload.fetch('backend')).to eq('postgres')
    expect(payload.fetch('job_id')).to start_with('roda-probe-')
  end
end
