# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Workflow
    # Immutable inspection view for one workflow history journal.
    class HistorySnapshot
      attr_reader :batch_id,
                  :captured_at,
                  :entries,
                  :workflow_family,
                  :workflow_id,
                  :workflow_version

      def initialize(**attributes)
        attributes = Attributes.new(attributes)
        @workflow_id = attributes.workflow_id
        @workflow_family = attributes.workflow_family
        @workflow_version = attributes.workflow_version
        @batch_id = attributes.batch_id
        @captured_at = attributes.captured_at
        @entries = attributes.entries
        freeze
      end

      # Validates and exposes workflow-history snapshot attributes.
      class Attributes
        REQUIRED_ATTRIBUTES = %i[
          workflow_id
          batch_id
          captured_at
          entries
        ].freeze
        OPTIONAL_ATTRIBUTES = %i[
          workflow_family
          workflow_version
        ].freeze
        SUPPORTED_ATTRIBUTES = (REQUIRED_ATTRIBUTES + OPTIONAL_ATTRIBUTES).freeze

        def initialize(attributes)
          @attributes = attributes
          validate_keys
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

        def captured_at
          Timestamp.new(:captured_at, fetch(:captured_at)).to_time
        end

        def entries
          EntryList.new(fetch(:entries)).to_a
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
      end

      # Normalizes workflow history entries into immutable arrays.
      class EntryList
        def initialize(entries)
          @entries = entries
        end

        def to_a
          raise InvalidExecutionError, 'entries must be an Array of Karya::Workflow::HistoryEntry' unless entries.is_a?(Array)

          entries.each do |entry|
            raise InvalidExecutionError, 'entries must be Karya::Workflow::HistoryEntry instances' unless entry.is_a?(HistoryEntry)
          end

          entries.dup.freeze
        end

        private

        attr_reader :entries
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

      private_constant :Attributes, :EntryList, :Timestamp
    end
  end
end
