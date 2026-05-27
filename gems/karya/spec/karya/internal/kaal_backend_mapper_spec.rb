# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'kaal'
require 'karya/internal/kaal_backend_mapper'
require 'redis'
require 'sequel'

RSpec.describe Karya::Internal::KaalBackendMapper do
  around do |example|
    original_configuration = Kaal.configuration
    Kaal.reset_configuration!
    example.run
  ensure
    Kaal.reset_configuration!
    Kaal.instance_variable_set(:@configuration, original_configuration)
  end

  describe '.build' do
    it 'maps the in-memory backend directly to Kaal memory' do
      backend = described_class.build(backend_class: Karya::Backend::InMemory, backend_options: {})

      expect(backend).to be_a(Kaal::Backend::MemoryAdapter)
    end

    it 'maps the redis backend to Kaal redis with the same url and namespace' do
      fake_redis = instance_double(Redis)
      fake_backend = instance_double(Kaal::Backend::RedisAdapter)
      allow(Redis).to receive(:new).with(url: 'redis://127.0.0.1:6379/7').and_return(fake_redis)
      allow(Kaal::Backend::RedisAdapter).to receive(:new).with(fake_redis, namespace: 'redis-spec').and_return(fake_backend)

      backend = described_class.build(
        backend_class: Karya::Backend::Redis,
        backend_options: { url: 'redis://127.0.0.1:6379/7', namespace: 'redis-spec' }
      )

      expect(backend).to eq(fake_backend)
    end

    it 'falls back to the default namespace when the configured namespace is blank' do
      fake_redis = instance_double(Redis)
      fake_backend = instance_double(Kaal::Backend::RedisAdapter)
      allow(Redis).to receive(:new).with(url: 'redis://127.0.0.1:6379/8').and_return(fake_redis)
      allow(Kaal::Backend::RedisAdapter).to receive(:new).with(fake_redis, namespace: 'karya').and_return(fake_backend)

      backend = described_class.build(
        backend_class: Karya::Backend::Redis,
        backend_options: { url: 'redis://127.0.0.1:6379/8', namespace: '' }
      )

      expect(backend).to eq(fake_backend)
    end

    it 'maps sqlite, postgres, and mysql to the matching Kaal SQL backends' do
      fake_database = instance_double(Sequel::Database)
      allow(Sequel).to receive(:connect).with('sqlite:///tmp/karya.sqlite3').and_return(fake_database)
      allow(Sequel).to receive(:connect).with('postgres://localhost/karya').and_return(fake_database)
      allow(Sequel).to receive(:connect).with('mysql2://localhost/karya').and_return(fake_database)

      sqlite_backend = instance_double(Kaal::Backend::SQLite)
      postgres_backend = instance_double(Kaal::Backend::Postgres)
      mysql_backend = instance_double(Kaal::Backend::MySQL)
      allow(Kaal::Backend::SQLite).to receive(:new).with(database: fake_database, namespace: 'sqlite-spec').and_return(sqlite_backend)
      allow(Kaal::Backend::Postgres).to receive(:new).with(database: fake_database, namespace: 'postgres-spec').and_return(postgres_backend)
      allow(Kaal::Backend::MySQL).to receive(:new).with(database: fake_database, namespace: 'mysql-spec').and_return(mysql_backend)

      expect(
        described_class.build(
          backend_class: Karya::Backend::SQLite,
          backend_options: { url: 'sqlite3:///tmp/karya.sqlite3', namespace: 'sqlite-spec' }
        )
      ).to eq(sqlite_backend)
      expect(
        described_class.build(
          backend_class: Karya::Backend::Postgres,
          backend_options: { url: 'postgres://localhost/karya', namespace: 'postgres-spec' }
        )
      ).to eq(postgres_backend)
      expect(
        described_class.build(
          backend_class: Karya::Backend::MySQL,
          backend_options: { url: 'mysql2://localhost/karya', namespace: 'mysql-spec' }
        )
      ).to eq(mysql_backend)
    end

    it 'returns nil for unsupported backend classes' do
      unsupported_backend = Class.new do
        include Karya::Backend::Base

        def identifier = 'custom'
        def build_queue_store = Karya::QueueStore::InMemory.new
      end

      expect(described_class.build(backend_class: unsupported_backend, backend_options: {})).to be_nil
    end
  end

  describe '.synchronize!' do
    it 'writes the mapped backend only when Kaal is still unset' do
      mapped_backend = instance_double(Kaal::Backend::MemoryAdapter)
      allow(described_class).to receive(:build).and_return(mapped_backend)

      expect(
        described_class.synchronize!(backend_class: Karya::Backend::InMemory, backend_options: {})
      ).to eq(mapped_backend)
      expect(Kaal.configuration.backend).to eq(mapped_backend)
    end

    it 'preserves an explicit preconfigured Kaal backend' do
      explicit_backend = Kaal::Backend::MemoryAdapter.new
      Kaal.configuration.backend = explicit_backend

      expect(
        described_class.synchronize!(backend_class: Karya::Backend::InMemory, backend_options: {})
      ).to eq(explicit_backend)
      expect(Kaal.configuration.backend).to eq(explicit_backend)
    end
  end

  describe 'dependency loading' do
    it 'raises an actionable error when the Redis dependency is unavailable' do
      allow(described_class).to receive(:require).with('redis').and_raise(LoadError, 'cannot load such file -- redis')

      expect do
        described_class.send(:require_redis!)
      end.to raise_error(
        LoadError,
        /cannot load such file -- redis while aligning the Kaal Redis backend/
      )
    end

    it 'raises an actionable error when the Sequel dependency is unavailable' do
      allow(described_class).to receive(:require).with('sequel').and_raise(LoadError, 'cannot load such file -- sequel')

      expect do
        described_class.send(:require_sequel!)
      end.to raise_error(
        LoadError,
        /cannot load such file -- sequel while aligning the Kaal SQL backend/
      )
    end
  end
end
