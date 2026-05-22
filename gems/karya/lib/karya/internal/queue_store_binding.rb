# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    # Captures and restores the process-global queue-store configuration.
    module QueueStoreBinding
      # Immutable snapshot of whether the queue-store ivar existed and what it held.
      Snapshot = Struct.new(:defined, :queue_store, keyword_init: true)

      module_function

      def capture
        Snapshot.new(
          defined: Karya.instance_variable_defined?(:@queue_store),
          queue_store: Karya.instance_variable_get(:@queue_store)
        )
      end

      def restore(snapshot)
        return unless snapshot

        if snapshot.defined
          Karya.configure_queue_store(snapshot.queue_store)
        else
          remove_configured_queue_store
        end
      end

      def remove_configured_queue_store
        return unless Karya.instance_variable_defined?(:@queue_store)

        Karya.send(:remove_instance_variable, :@queue_store)
      end
      private_class_method :remove_configured_queue_store
    end
  end
end
