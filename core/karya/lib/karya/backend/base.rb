# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Backend
    # Shared backend contract above the queue-store persistence API.
    module Base
      def identifier
        descriptor.identifier
      end

      def classification
        descriptor.classification
      end

      def capabilities
        descriptor.capabilities
      end

      def descriptor
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      def build_queue_store
        raise NotImplementedError, "#{self.class} must implement ##{__method__}"
      end

      def before_start(queue_store:)
        _queue_store = queue_store
        nil
      end

      def after_stop(queue_store:)
        _queue_store = queue_store
        nil
      end
    end
  end
end
