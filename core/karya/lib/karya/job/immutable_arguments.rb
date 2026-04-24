# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../internal/immutable_argument_graph'

module Karya
  class Job
    # Normalizes and deeply freezes job arguments so job instances remain immutable.
    class ImmutableArguments
      IMMUTABLE_SCALAR_CLASSES = Internal::ImmutableArgumentGraph::IMMUTABLE_SCALAR_CLASSES
      DUPLICABLE_SCALAR_CLASSES = Internal::ImmutableArgumentGraph::DUPLICABLE_SCALAR_CLASSES
      private_constant :IMMUTABLE_SCALAR_CLASSES
      private_constant :DUPLICABLE_SCALAR_CLASSES

      def initialize(arguments)
        @arguments = arguments
      end

      def normalize
        Internal::ImmutableArgumentGraph.new(arguments, error_class: InvalidJobAttributeError).normalize
      end

      private

      attr_reader :arguments
    end
  end
end
