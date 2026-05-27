# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../base'

module Karya
  module JobLifecycle
    # Raised when a job state is not part of the canonical lifecycle.
    class InvalidJobStateError < Karya::Error; end

    # Raised when a lifecycle transition is not allowed.
    class InvalidJobTransitionError < Karya::Error; end
  end
end
