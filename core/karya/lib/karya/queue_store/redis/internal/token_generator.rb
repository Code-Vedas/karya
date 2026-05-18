# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'

module Karya
  module QueueStore
    class Redis
      module Internal
        # Stable token generator proxy that supports replay overrides without swapping shared owner state.
        class TokenGenerator
          def initialize(owner:)
            @owner = owner
          end

          def call
            owner.send(:journal_replay_token_base) || SecureRandom.uuid
          end

          private

          attr_reader :owner
        end
      end
    end
  end
end
