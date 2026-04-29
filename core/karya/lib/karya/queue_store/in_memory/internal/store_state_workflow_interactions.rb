# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Owner-local workflow interaction inbox storage for StoreState.
        class StoreState
          # Owner-local workflow interaction inbox keyed by workflow batch id.
          class WorkflowInteractions
            EMPTY = [].freeze
            MAX_INTERACTIONS_PER_BATCH = 100
            private_constant :EMPTY, :MAX_INTERACTIONS_PER_BATCH

            def initialize
              @by_batch_id = {}
              @max_interactions_per_batch = MAX_INTERACTIONS_PER_BATCH
            end

            def for_batch(batch_id)
              with_inbox(batch_id, fallback: EMPTY, &:to_a)
            end

            def includes?(batch_id:, kind:, name:)
              with_inbox(batch_id, fallback: false) { |inbox| inbox.includes?(kind:, name:) }
            end

            def received_at_for(batch_id:, kind:, name:)
              with_inbox(batch_id, fallback: nil) { |inbox| inbox.received_at_for(kind:, name:) }
            end

            def register(batch_id:, interaction:)
              current_inbox(batch_id).append(interaction).to_a
            end

            def configure(batch_id:, supported_keys:)
              current_inbox(batch_id).configure(supported_keys:)
            end

            def delete_by_batch(batch_id)
              with_inbox(batch_id, fallback: EMPTY, delete: true, &:to_a)
            end

            private

            attr_reader :max_interactions_per_batch

            def current_inbox(batch_id)
              @by_batch_id[batch_id] ||= Inbox.new(max_size: max_interactions_per_batch)
            end

            def with_inbox(batch_id, fallback:, delete: false)
              inbox = delete ? @by_batch_id.delete(batch_id) : @by_batch_id[batch_id]
              return fallback unless inbox

              yield inbox
            end

            # Owner-local bounded interaction buffer for one workflow batch.
            class Inbox
              def initialize(max_size:)
                @max_size = max_size
                @interactions = []
                @to_a = EMPTY
                @received_at_by_key = {}
                @supported_keys = {}.freeze
              end

              def append(interaction)
                interactions << interaction
                track([interaction.kind, interaction.name], interaction.received_at)
                interactions.shift if interactions.length > max_size
                @to_a = nil
                self
              end

              def configure(supported_keys:)
                normalized_supported_keys =
                  if supported_keys.is_a?(Hash)
                    supported_keys.keys.to_h { |key| [key, true] }
                  else
                    supported_keys.to_h { |key| [key, true] }
                  end

                @supported_keys = normalized_supported_keys.freeze
                rebuild_received_at_index
                self
              end

              def to_a
                @to_a ||= interactions.dup.freeze
              end

              def includes?(kind:, name:)
                received_at_by_key.key?([kind, name])
              end

              def received_at_for(kind:, name:)
                received_at_by_key[[kind, name]]
              end

              private

              attr_reader :interactions, :max_size, :received_at_by_key, :supported_keys

              def rebuild_received_at_index
                received_at_by_key.clear
                interactions.each { |interaction| track([interaction.kind, interaction.name], interaction.received_at) }
              end

              def track(key, received_at)
                return unless supported_keys.key?(key)

                received_at_by_key[key] = received_at
              end
            end
          end

          private_constant :WorkflowInteractions
        end
      end
    end
  end
end
