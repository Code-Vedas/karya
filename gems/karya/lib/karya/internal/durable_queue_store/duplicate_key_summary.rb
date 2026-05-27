# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Compact duplicate-key log formatting that avoids dumping arbitrarily long keys.
      class DuplicateKeySummary
        MAX_PREVIEW_LENGTH = 64

        def initialize(key)
          @key = key
        end

        def to_s
          "#{preview.inspect} (length=#{key.length})"
        end

        private

        attr_reader :key

        def preview
          return key unless key.length > MAX_PREVIEW_LENGTH

          "#{key[0, MAX_PREVIEW_LENGTH]}..."
        end
      end
    end
  end
end
