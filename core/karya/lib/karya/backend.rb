# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  # Raised when backend selection input cannot be normalized into a supported identifier.
  class InvalidBackendSelectionError < Error; end

  # Raised when a caller refers to a backend outside the supported backend set.
  class UnsupportedBackendError < Error; end

  # Namespace for backend selection, capability, and lifecycle contracts.
  module Backend
    autoload :Base, 'karya/backend/base'
    autoload :Capabilities, 'karya/backend/capabilities'
    autoload :Descriptor, 'karya/backend/descriptor'
    autoload :InMemory, 'karya/backend/in_memory'
    autoload :Selection, 'karya/backend/selection'
  end
end
