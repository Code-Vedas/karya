# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../internal/runtime_support/shutdown_state'

module Karya
  class Worker
    # Tracks child-worker shutdown transitions across normal, drain, and force-stop states.
    class ShutdownController < Internal::RuntimeSupport::ShutdownState
      def self.inactive
        @inactive ||= InactiveShutdownController.new
      end
    end
  end
end
