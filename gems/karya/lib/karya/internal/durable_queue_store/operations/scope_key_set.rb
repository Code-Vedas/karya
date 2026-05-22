# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Produces normalized queue, handler, and explicit policy scope keys for a job.
        class ScopeKeySet
          def initialize(job:, explicit_scope:)
            @job = job
            @explicit_scope = explicit_scope
          end

          attr_reader :job, :explicit_scope

          def to_a
            keys = ["queue:#{job.queue}", "handler:#{job.handler}"]
            explicit_key = explicit_scope&.key
            keys << explicit_key if explicit_key && !keys.include?(explicit_key)
            keys
          end
        end
      end
    end
  end
end
