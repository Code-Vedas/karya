# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../base'
require_relative '../backend'
require_relative '../queue_store/in_memory'

module Karya
  module Backend
    # Quick-start backend wrapper around the single-process reference queue store.
    class InMemory
      include Base

      def initialize(**options)
        unless options.empty?
          raise InvalidBackendConfigurationError,
                "Karya::Backend::InMemory does not accept backend options: #{options.keys.map(&:inspect).join(', ')}"
        end

        @identifier = 'in_memory'
        @queue_store_class = QueueStore::InMemory
      end

      attr_reader :identifier

      def build_queue_store
        queue_store_class.new
      end

      private

      attr_reader :queue_store_class
    end
  end
end
