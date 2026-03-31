# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module RuntimeSupport
      # Shared validation for signal-subscriber restorer callbacks.
      class SignalRestorer
        def initialize(value, error_class:, message:)
          @value = value
          @error_class = error_class
          @message = message
        end

        def normalize
          value.public_method(:call)
          value
        rescue NameError
          raise error_class, message
        end

        private

        attr_reader :error_class, :message, :value
      end
    end
  end
end
