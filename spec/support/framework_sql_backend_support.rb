# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module FrameworkSQLBackendSupport
  UNDEFINED = Object.new.freeze

  def preserve_backend_configuration
    original_backend_class = Karya.instance_variable_defined?(:@backend_class) ? Karya.instance_variable_get(:@backend_class) : UNDEFINED
    original_backend_options = Karya.instance_variable_defined?(:@backend_options) ? Karya.instance_variable_get(:@backend_options) : UNDEFINED
    yield
  ensure
    restore_backend_ivar(:@backend_class, original_backend_class)
    restore_backend_ivar(:@backend_options, original_backend_options)
  end

  def with_postgres_backend(prefix:, namespace:)
    preserve_backend_configuration do
      with_postgres_database(prefix:) do |database_url|
        Karya.configure_backend(Karya::Backend::Postgres, url: database_url, namespace:)
        yield database_url
      end
    end
  end

  def with_mysql_backend(prefix:, namespace:)
    preserve_backend_configuration do
      with_mysql_database(prefix:) do |database_url|
        Karya.configure_backend(Karya::Backend::MySQL, url: database_url, namespace:)
        yield database_url
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
end

RSpec.configure do |config|
  config.include FrameworkSQLBackendSupport
end
