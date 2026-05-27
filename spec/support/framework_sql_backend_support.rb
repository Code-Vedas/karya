# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'

module FrameworkSQLBackendSupport
  UNDEFINED = Object.new.freeze
  FRAMEWORK_E2E_ENV_KEYS = %w[
    KARYA_FRAMEWORK_E2E_BACKEND
    KARYA_FRAMEWORK_E2E_DATABASE_URL
    KARYA_FRAMEWORK_E2E_NAMESPACE
    KARYA_FRAMEWORK_E2E_KAAL_BACKEND
    KARYA_FRAMEWORK_E2E_KAAL_DATABASE_URL
    KARYA_FRAMEWORK_E2E_KAAL_NAMESPACE
  ].freeze

  def preserve_backend_configuration
    original_backend_class = Karya.instance_variable_defined?(:@backend_class) ? Karya.instance_variable_get(:@backend_class) : UNDEFINED
    original_backend_options = Karya.instance_variable_defined?(:@backend_options) ? Karya.instance_variable_get(:@backend_options) : UNDEFINED
    original_queue_store = Karya.instance_variable_defined?(:@queue_store) ? Karya.instance_variable_get(:@queue_store) : UNDEFINED
    original_kaal_backend = Kaal.configuration.backend
    Karya::FrameworkRuntime.reset_shared_runtime!
    Kaal.reset_registry!
    Kaal.reset_coordinator!
    yield
  ensure
    Karya::FrameworkRuntime.reset_shared_runtime!
    restore_backend_ivar(:@backend_class, original_backend_class)
    restore_backend_ivar(:@backend_options, original_backend_options)
    restore_backend_ivar(:@queue_store, original_queue_store)
    Kaal.reset_configuration!
    Kaal.configuration.backend = original_kaal_backend
    Kaal.reset_registry!
    Kaal.reset_coordinator!
  end

  def with_postgres_backend(prefix:, namespace:)
    preserve_backend_configuration do
      with_postgres_database(prefix:) do |database_url|
        with_framework_config_env(backend: 'postgres', database_url:, namespace:) do
          Karya.configure_backend(Karya::Backend::Postgres, url: database_url, namespace:)
          yield database_url
        end
      end
    end
  end

  def with_mysql_backend(prefix:, namespace:)
    preserve_backend_configuration do
      with_mysql_database(prefix:) do |database_url|
        with_framework_config_env(backend: 'mysql', database_url:, namespace:) do
          Karya.configure_backend(Karya::Backend::MySQL, url: database_url, namespace:)
          yield database_url
        end
      end
    end
  end

  def with_sqlite_backend(prefix:, namespace:)
    preserve_backend_configuration do
      with_sqlite_database(prefix:) do |database_url|
        with_framework_config_env(backend: 'sqlite', database_url:, namespace:) do
          Karya.configure_backend(Karya::Backend::SQLite, url: database_url, namespace:)
          yield database_url
        end
      end
    end
  end

  def with_redis_backend(namespace:)
    preserve_backend_configuration do
      require 'redis'

      redis_url = ENV.fetch('KARYA_REDIS_URL') { ENV.fetch('REDIS_URL') }
      resolved_namespace = "#{namespace}_#{SecureRandom.hex(6)}"

      delete_redis_namespace(redis_url:, namespace: resolved_namespace)
      with_framework_config_env(backend: 'redis', database_url: redis_url, namespace: resolved_namespace) do
        Karya.configure_backend(Karya::Backend::Redis, url: redis_url, namespace: resolved_namespace)
        yield redis_url
      end
    ensure
      delete_redis_namespace(redis_url:, namespace: resolved_namespace) if defined?(resolved_namespace)
    end
  end

  def with_in_memory_backend
    preserve_backend_configuration do
      with_framework_config_env(backend: 'in_memory', database_url: nil, namespace: 'karya') do
        Karya.configure_backend(Karya::Backend::InMemory)
        Karya.configure_queue_store(Karya::Backend::InMemory.new.build_queue_store)
        yield
      end
    end
  end

  def restore_backend_ivar(name, value)
    if value.equal?(UNDEFINED)
      Karya.remove_instance_variable(name) if Karya.instance_variable_defined?(name)
    else
      Karya.instance_variable_set(name, value)
    end
  end
  private :restore_backend_ivar

  def delete_redis_namespace(redis_url:, namespace:)
    client = Redis.new(url: redis_url)
    keys = client.scan_each(match: "#{namespace}:*").to_a
    client.del(*keys) unless keys.empty?
  ensure
    client&.close
  end
  private :delete_redis_namespace

  def with_framework_config_env(backend:, database_url:, namespace:)
    previous_values = {}
    kaal_backend = backend == 'in_memory' ? 'memory' : backend
    kaal_database_url = if backend == 'sqlite' && database_url
                          database_url.sub(/\Asqlite3:\/\//, 'sqlite://')
                        else
                          database_url
                        end
    previous_values = FRAMEWORK_E2E_ENV_KEYS.to_h { |key| [key, ENV[key]] }
    ENV['KARYA_FRAMEWORK_E2E_BACKEND'] = backend
    database_url.nil? ? ENV.delete('KARYA_FRAMEWORK_E2E_DATABASE_URL') : ENV['KARYA_FRAMEWORK_E2E_DATABASE_URL'] = database_url
    ENV['KARYA_FRAMEWORK_E2E_NAMESPACE'] = namespace
    ENV['KARYA_FRAMEWORK_E2E_KAAL_BACKEND'] = kaal_backend
    kaal_database_url.nil? ? ENV.delete('KARYA_FRAMEWORK_E2E_KAAL_DATABASE_URL') : ENV['KARYA_FRAMEWORK_E2E_KAAL_DATABASE_URL'] = kaal_database_url
    ENV['KARYA_FRAMEWORK_E2E_KAAL_NAMESPACE'] = namespace
    yield
  ensure
    previous_values.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end
  private :with_framework_config_env
end

RSpec.configure do |config|
  config.include FrameworkSQLBackendSupport
end
