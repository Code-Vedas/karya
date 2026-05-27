# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Backend rows and metadata loaded for one durable operation.
      class OperationContext
        def initialize(namespace:, request:, metadata:, rows:)
          @namespace = namespace
          @request = request
          @metadata = metadata
          @rows = rows
        end

        attr_reader :metadata, :namespace, :request, :rows
      end
    end
  end
end
