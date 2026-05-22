# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class MySQL
      module Internal
        # Loads optional runtime dependencies for the MySQL-backed queue store.
        module DependencyLoader
          module_function

          def require_mysql2!
            require 'mysql2'
          rescue LoadError => e
            raise LoadError,
                  "#{e.message}. Add `gem 'mysql2'` to your Gemfile to use Karya::Backend::MySQL and Karya::QueueStore::MySQL.",
                  cause: e
          end
        end
      end
    end
  end
end
