# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Encapsulates subscription handler matching for reservation scans.
        class HandlerMatcher
          def initialize(handler_names)
            if handler_names
              raise InvalidQueueStoreOperationError, 'handler_names must be an Array' unless handler_names.is_a?(Array)

              @match_all = false
              @handler_names = normalize_present_handler_names(handler_names)
            else
              @match_all = true
              @handler_names = {}.freeze
            end
          end

          def include?(handler_name)
            match_all || handler_names.include?(handler_name)
          end

          def subscription_key_part
            return nil if match_all

            handler_names.keys.sort.freeze
          end

          private

          attr_reader :handler_names, :match_all

          def normalize_present_handler_names(handler_names)
            normalized_names = handler_names.map do |name|
              raise InvalidQueueStoreOperationError, 'handler_names entries must be Strings' unless name.is_a?(String)

              Primitives::Identifier.new(:handler, name, error_class: InvalidQueueStoreOperationError).normalize
            end
            raise InvalidQueueStoreOperationError, 'handler_names must be present' if normalized_names.empty?

            normalized_names.to_h { |name| [name, true] }.freeze
          end
        end
      end
    end
  end
end
