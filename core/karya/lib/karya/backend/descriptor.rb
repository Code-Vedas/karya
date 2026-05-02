# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../primitives/identifier'

module Karya
  module Backend
    # Immutable backend identity description.
    class Descriptor
      attr_reader :identifier

      def initialize(identifier:)
        @identifier = Selection.normalize_identifier(identifier)
        freeze
      end
    end
  end
end
