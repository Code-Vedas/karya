# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  # Raised when backend configuration is invalid.
  class InvalidBackendConfigurationError < Error; end

  # Namespace for backend interface and lifecycle contracts.
  module Backend
    autoload :Base, 'karya/backend/base'
    autoload :InMemory, 'karya/backend/in_memory'
    autoload :MySQL, 'karya/backend/mysql'
    autoload :Postgres, 'karya/backend/postgres'
    autoload :Redis, 'karya/backend/redis'
  end
end
