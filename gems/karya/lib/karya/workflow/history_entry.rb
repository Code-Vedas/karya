# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'json'

module Karya
  module Workflow
    # Immutable inspection row for one workflow history event.
    class HistoryEntry
      KINDS = %i[workflow step interaction control rollback child_workflow].freeze

      attr_reader :action, :details, :kind, :occurred_at

      def initialize(**attributes)
        attributes = Attributes.new(attributes)
        @kind = attributes.kind
        @action = attributes.action
        @occurred_at = attributes.occurred_at
        @identity = attributes.identity
        @linkage = attributes.linkage
        @details = attributes.details
        freeze
      end

      def workflow_id = identity.workflow_id

      def workflow_family = identity.workflow_family

      def workflow_version = identity.workflow_version

      def batch_id = identity.batch_id

      def step_id = linkage.step_id

      def job_id = linkage.job_id

      def child_batch_id = linkage.child_batch_id

      # Validates and exposes history entry attributes.
      class Attributes
        REQUIRED_ATTRIBUTES = %i[
          kind
          action
          occurred_at
          workflow_id
          batch_id
        ].freeze
        OPTIONAL_ATTRIBUTES = %i[
          workflow_family
          workflow_version
          step_id
          job_id
          child_batch_id
          details
        ].freeze
        SUPPORTED_ATTRIBUTES = (REQUIRED_ATTRIBUTES + OPTIONAL_ATTRIBUTES).freeze

        def initialize(attributes)
          @attributes = attributes
          validate_keys
        end

        def kind
          normalized_kind = Kind.new(fetch(:kind)).to_sym
          return normalized_kind if KINDS.include?(normalized_kind)

          raise InvalidExecutionError, 'kind must be a supported workflow history kind'
        end

        def action
          Workflow.send(:normalize_execution_identifier, :action, fetch(:action))
        end

        def occurred_at
          Timestamp.new(:occurred_at, fetch(:occurred_at)).to_time
        end

        def workflow_id
          Workflow.send(:normalize_identifier, :workflow_id, fetch(:workflow_id))
        end

        def workflow_family
          value = attributes.fetch(:workflow_family, workflow_id)
          Workflow.send(:normalize_identifier, :workflow_family, value)
        end

        def workflow_version
          value = attributes.fetch(:workflow_version, 'v1')
          Workflow.send(:normalize_identifier, :workflow_version, value)
        end

        def batch_id
          Workflow.send(:normalize_batch_identifier, :batch_id, fetch(:batch_id))
        end

        def step_id
          optional_execution_identifier(:step_id)
        end

        def job_id
          optional_execution_identifier(:job_id)
        end

        def child_batch_id
          optional_batch_identifier(:child_batch_id)
        end

        def details
          Payload.new(attributes.fetch(:details, {})).to_h
        end

        def identity
          Identity.new(
            workflow_id:,
            workflow_family:,
            workflow_version:,
            batch_id:
          )
        end

        def linkage
          Linkage.new(
            step_id:,
            job_id:,
            child_batch_id:
          )
        end

        private

        attr_reader :attributes

        def fetch(name)
          attributes.fetch(name) { raise ArgumentError, "missing keyword: :#{name}" }
        end

        def validate_keys
          unknown_keys = attributes.keys - SUPPORTED_ATTRIBUTES
          return if unknown_keys.empty?

          raise ArgumentError, "unknown keyword: :#{unknown_keys.first}"
        end

        def optional_execution_identifier(name)
          value = attributes.fetch(name, nil)
          return nil unless value

          Workflow.send(:normalize_execution_identifier, name, value)
        end

        def optional_batch_identifier(name)
          value = attributes.fetch(name, nil)
          return nil unless value

          Workflow.send(:normalize_batch_identifier, name, value)
        end
      end

      # Immutable workflow identity for one history entry.
      class Identity
        attr_reader :batch_id, :workflow_family, :workflow_id, :workflow_version

        def initialize(workflow_id:, workflow_family:, workflow_version:, batch_id:)
          @workflow_id = workflow_id
          @workflow_family = workflow_family
          @workflow_version = workflow_version
          @batch_id = batch_id
          freeze
        end
      end

      # Immutable step/job linkage for one history entry.
      class Linkage
        attr_reader :child_batch_id, :job_id, :step_id

        def initialize(step_id:, job_id:, child_batch_id:)
          @step_id = step_id
          @job_id = job_id
          @child_batch_id = child_batch_id
          freeze
        end
      end

      # Normalizes one history-entry kind.
      class Kind
        def initialize(value)
          @value = value
        end

        def to_sym
          raise InvalidExecutionError, 'kind must be a Symbol or String' unless value.is_a?(String) || value.is_a?(Symbol)

          value.to_sym
        end

        private

        attr_reader :value
      end

      # Normalizes and deep-freezes a JSON-compatible details payload.
      class Payload
        MAX_DETAILS_BYTES = 16 * 1024
        private_constant :MAX_DETAILS_BYTES

        def initialize(payload)
          @payload = payload
        end

        def to_h
          raise InvalidExecutionError, 'details must be a Hash' unless payload.is_a?(Hash)

          normalized = normalize_hash(payload)
          validate_size(normalized)
        end

        private

        attr_reader :payload

        def validate_size(normalized)
          details_bytesize = JSON.generate(normalized).bytesize
          return normalized if details_bytesize <= MAX_DETAILS_BYTES

          raise InvalidExecutionError, "details exceeds #{MAX_DETAILS_BYTES} bytes"
        rescue JSON::GeneratorError => e
          raise InvalidExecutionError, 'details must be JSON-encodable', cause: e
        end

        def normalize_hash(hash)
          hash.each_with_object({}) do |(key, value), normalized|
            raise InvalidExecutionError, 'details keys must be Strings' unless key.is_a?(String)

            normalized[key.dup.freeze] = normalize_value(value)
          end.freeze
        end

        def normalize_value(value)
          case value
          when NilClass, TrueClass, FalseClass, Numeric
            value
          when String
            value.dup.freeze
          when Array
            value.map { |entry| normalize_value(entry) }.freeze
          when Hash
            normalize_hash(value)
          else
            raise InvalidExecutionError, 'details values must be JSON-compatible'
          end
        end
      end

      # Normalizes timestamps into immutable values.
      class Timestamp
        def initialize(name, value)
          @name = name
          @value = value
        end

        def to_time
          return value.dup.freeze if value.is_a?(Time)

          raise InvalidExecutionError, "#{name} must be a Time"
        end

        private

        attr_reader :name, :value
      end

      private

      attr_reader :identity, :linkage

      private_constant :Attributes, :Identity, :Kind, :KINDS, :Linkage, :Payload, :Timestamp
    end
  end
end
