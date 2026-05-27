# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Public return value and persistence intent for one durable operation.
      class OperationResult
        def initialize(value:, mutation_plan:, persist:)
          @value = value
          @mutation_plan = mutation_plan
          @persist = persist
        end

        attr_reader :mutation_plan, :value

        def persist?
          @persist
        end
      end
    end
  end
end
