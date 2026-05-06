# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class Redis
      module Internal
        # Loads optional runtime dependencies for the Redis-backed queue store.
        module DependencyLoader
          module_function

          def require_redis!
            require 'redis'
          rescue LoadError => e
            raise LoadError,
                  "#{e.message}. Add `gem 'redis', '~> 5.4'` to your Gemfile to use Karya::Backend::Redis and Karya::QueueStore::Redis."
          end
        end
      end
    end
  end
end
