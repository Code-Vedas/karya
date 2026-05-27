# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class Postgres
      module Internal
        # Loads optional runtime dependencies for the Postgres-backed queue store.
        module DependencyLoader
          module_function

          def require_pg!
            require 'pg'
          rescue LoadError => e
            raise LoadError,
                  "#{e.message}. Add `gem 'pg'` to your Gemfile to use Karya::Backend::Postgres and Karya::QueueStore::Postgres.",
                  cause: e
          end
        end
      end
    end
  end
end
