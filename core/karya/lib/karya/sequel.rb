# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'fileutils'

require_relative 'internal/postgres_schema_catalog'

module Karya
  # Sequel migration/install support for the Postgres backend.
  module Sequel
    module_function

    def install_postgres_migration(target_dir:, migration_name: 'create_karya_postgres_backend')
      require_sequel!

      normalized_name = normalize_migration_name(migration_name)
      file_name = "#{timestamp}_#{normalized_name}.rb"
      path = File.expand_path(file_name, target_dir)

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, Karya::Internal::PostgresSchemaCatalog.render_sequel_migration)
      path
    end

    def require_sequel!
      require 'sequel'
    rescue LoadError => e
      raise LoadError,
            "#{e.message}. Add `gem 'sequel'` to your Gemfile to use Karya::Sequel Postgres migration support.",
            cause: e
    end

    def normalize_migration_name(name)
      normalized = name.to_s.each_char.with_object(+'') do |char, buffer|
        if letter?(char) || digit?(char)
          buffer << char.downcase
        elsif !buffer.empty? && !buffer.end_with?('_')
          buffer << '_'
        end
      end.delete_suffix('_')
      return normalized unless normalized.empty?

      'create_karya_postgres_backend'
    end

    def timestamp
      Time.now.utc.strftime('%Y%m%d%H%M%S')
    end

    def letter?(char)
      char.between?('a', 'z') || char.between?('A', 'Z')
    end

    def digit?(char)
      char.between?('0', '9')
    end
  end
end
