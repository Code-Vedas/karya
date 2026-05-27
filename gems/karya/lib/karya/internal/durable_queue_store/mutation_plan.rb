# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Exact row-level writes and deletes for one durable operation.
      class MutationPlan
        def initialize(metadata_updates: {}, inserts: {}, updates: {}, deletes: {})
          @metadata_updates = metadata_updates.freeze
          @inserts = normalize_groups(inserts)
          @updates = normalize_groups(updates)
          @deletes = normalize_groups(deletes)
        end

        attr_reader :deletes, :inserts, :metadata_updates, :updates

        def empty?
          metadata_updates.empty? && inserts.empty? && updates.empty? && deletes.empty?
        end

        private

        def normalize_groups(groups)
          groups.each_with_object({}) do |(name, rows), normalized|
            next if rows.empty?

            normalized[name] = rows.freeze
          end.freeze
        end
      end
    end
  end
end
