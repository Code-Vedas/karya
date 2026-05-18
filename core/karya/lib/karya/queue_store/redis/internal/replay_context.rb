# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class Redis
      module Internal
        # Thread-local replay state used to bypass persistence without swapping shared owner ivars.
        class ReplayContext
          PRESERVE_TOKEN_BASE = Object.new
          private_constant :PRESERVE_TOKEN_BASE

          def initialize(
            mutex_bypass_key: :karya_reference_queue_store_mutex_bypass,
            token_base_key: :karya_journal_replay_token_base
          )
            @mutex_bypass_key = mutex_bypass_key
            @token_base_key = token_base_key
          end

          def with_bypass(reservation_token_base: PRESERVE_TOKEN_BASE)
            current_thread = Thread.current
            previous_bypass = current_thread[@mutex_bypass_key]
            previous_token_base = current_thread[@token_base_key]
            current_thread[@mutex_bypass_key] = true
            current_thread[@token_base_key] = reservation_token_base unless reservation_token_base.equal?(PRESERVE_TOKEN_BASE)
            yield
          ensure
            current_thread[@token_base_key] = previous_token_base
            current_thread[@mutex_bypass_key] = previous_bypass
          end

          def bypass?
            Thread.current[@mutex_bypass_key] == true
          end

          def token_base
            Thread.current[@token_base_key]
          end
        end
      end
    end
  end
end
