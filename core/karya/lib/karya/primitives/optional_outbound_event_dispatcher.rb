# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Primitives
    # Validates optional outbound event dispatcher dependencies while allowing nil.
    class OptionalOutboundEventDispatcher < OptionalCallable
      def normalize
        return nil if [nil].include?(value)

        OutboundEventDispatcher.new(name, value, error_class:).normalize
      end
    end
  end
end
