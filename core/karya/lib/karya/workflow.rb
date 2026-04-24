# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'primitives/identifier'
require_relative 'workflow/batch'
require_relative 'workflow/batch_snapshot'
require_relative 'workflow/catalog'
require_relative 'workflow/dependency'
require_relative 'workflow/definition'
require_relative 'workflow/step'

module Karya
  # Canonical workflow composition model and Ruby-first authoring DSL.
  module Workflow
    # Raised when a workflow definition or composition graph is invalid.
    class InvalidDefinitionError < Error; end
    # Raised when a workflow batch or batch inspection request is invalid.
    class InvalidBatchError < Error; end
    # Raised when a workflow batch id conflicts with existing batch state.
    class DuplicateBatchError < InvalidBatchError; end
    # Raised when workflow batch state cannot be found.
    class UnknownBatchError < InvalidBatchError; end

    module_function

    def define(id, &block)
      builder = Builder.new(id)
      builder.instance_eval(&block) if block
      builder.to_definition
    end

    def catalog(definitions:)
      Catalog.new(definitions:)
    end

    def normalize_identifier(field_name, value)
      Primitives::Identifier.new(field_name, value, error_class: InvalidDefinitionError).normalize
    end
    module_function :normalize_identifier

    def normalize_batch_identifier(field_name, value)
      Primitives::Identifier.new(field_name, value, error_class: InvalidBatchError).normalize
    end
    module_function :normalize_batch_identifier

    # Owner-local DSL builder for workflow definition.
    class Builder
      def initialize(id)
        @id = id
        @steps = []
      end

      def step(id, handler:, arguments: {}, depends_on: nil)
        steps << Step.new(id:, handler:, arguments:, depends_on:)
        nil
      end

      def to_definition
        Definition.new(id:, steps:)
      end

      private

      attr_reader :id, :steps
    end

    private_constant :Builder
    private_class_method :normalize_identifier
    private_class_method :normalize_batch_identifier
  end
end
