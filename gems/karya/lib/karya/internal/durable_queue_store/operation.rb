# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Base durable operation object.
      class Operation
        def initialize(store:, request:, operation_name: nil)
          @operation_name = operation_name
          @store = store
          @request = request
        end

        attr_reader :operation_name, :request, :store

        def call(context:)
          raise NotImplementedError, "#{self.class} must implement #call"
        end
      end
    end
  end
end
