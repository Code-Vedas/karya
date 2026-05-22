# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Karya
  module Internal
    # Aligns the configured Karya backend with the published Kaal backend family.
    module KaalBackendMapper
      module_function

      def synchronize!(backend_class:, backend_options:, configuration: kaal_configuration)
        current_backend = configuration.backend
        return current_backend if current_backend

        backend = build(backend_class:, backend_options:)
        return nil unless backend

        configuration.backend = backend
      end

      def build(backend_class:, backend_options:)
        require_kaal!

        case backend_class.name
        when 'Karya::Backend::InMemory'
          Kaal::Backend::MemoryAdapter.new
        when 'Karya::Backend::Redis'
          build_redis_backend(backend_options)
        when 'Karya::Backend::SQLite'
          build_sql_backend(Kaal::Backend::SQLite, backend_options)
        when 'Karya::Backend::Postgres'
          build_sql_backend(Kaal::Backend::Postgres, backend_options)
        when 'Karya::Backend::MySQL'
          build_sql_backend(Kaal::Backend::MySQL, backend_options)
        end
      end

      def namespace_for(backend_options)
        namespace = backend_options.fetch(:namespace, 'karya')
        namespace.to_s.empty? ? 'karya' : namespace
      end

      def url_for(backend_options)
        backend_options.fetch(:url)
      end

      def build_redis_backend(backend_options)
        require_redis!
        Kaal::Backend::RedisAdapter.new(
          ::Redis.new(url: url_for(backend_options)),
          namespace: namespace_for(backend_options)
        )
      end

      def build_sql_backend(backend_class, backend_options)
        require_sequel!
        backend_class.new(
          database: ::Sequel.connect(sequel_database_url_for(url_for(backend_options))),
          namespace: namespace_for(backend_options)
        )
      end

      def sequel_database_url_for(database_url)
        return database_url.sub(%r{\Asqlite3://}, 'sqlite://') if database_url.start_with?('sqlite3://')

        database_url
      end

      def kaal_configuration
        require_kaal!
        Kaal.configuration
      end

      def require_kaal!
        require 'kaal'
      end

      def require_redis!
        require 'redis'
      rescue LoadError => e
        raise LoadError, "#{e.message} while aligning the Kaal Redis backend with the configured Karya backend"
      end

      def require_sequel!
        require 'sequel'
      rescue LoadError => e
        raise LoadError, "#{e.message} while aligning the Kaal SQL backend with the configured Karya backend"
      end
    end
  end
end
