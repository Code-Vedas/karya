# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class SQLite
      module Internal
        # Loads optional runtime dependencies for the SQLite-backed queue store.
        module DependencyLoader
          module_function

          def require_sqlite3!
            require 'sqlite3'
          rescue LoadError => e
            raise LoadError,
                  "#{e.message}. Add `gem 'sqlite3'` to your Gemfile to use Karya::Backend::SQLite and Karya::QueueStore::SQLite.",
                  cause: e
          end
        end
      end
    end
  end
end
