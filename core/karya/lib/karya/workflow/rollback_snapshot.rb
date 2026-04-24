# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../internal/dead_letter_reason'

module Karya
  module Workflow
    # Immutable inspection view for one workflow rollback request.
    class RollbackSnapshot
      attr_reader :compensation_count,
                  :compensation_job_ids,
                  :reason,
                  :requested_at,
                  :rollback_batch_id,
                  :workflow_batch_id

      def initialize(workflow_batch_id:, rollback_batch_id:, reason:, requested_at:, compensation_job_ids:)
        @workflow_batch_id = Workflow.send(:normalize_batch_identifier, :workflow_batch_id, workflow_batch_id)
        @rollback_batch_id = Workflow.send(:normalize_batch_identifier, :rollback_batch_id, rollback_batch_id)
        @reason = Reason.new(reason).normalize
        @requested_at = Timestamp.new(:requested_at, requested_at).to_time
        @compensation_job_ids = CompensationJobIds.new(compensation_job_ids).to_a
        @compensation_count = @compensation_job_ids.length
        freeze
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

      # Normalizes rollback compensation job ids while allowing no-op rollback.
      class CompensationJobIds
        def initialize(compensation_job_ids)
          @compensation_job_ids = compensation_job_ids
        end

        def to_a
          raise InvalidExecutionError, 'compensation_job_ids must be an Array' unless compensation_job_ids.is_a?(Array)

          normalized_job_ids = compensation_job_ids.map do |job_id|
            Workflow.send(:normalize_execution_identifier, :compensation_job_id, job_id)
          end
          duplicate_job_id = normalized_job_ids.tally.find { |_job_id, count| count > 1 }&.first
          raise InvalidExecutionError, "duplicate compensation job id #{duplicate_job_id.inspect}" if duplicate_job_id

          normalized_job_ids.freeze
        end

        private

        attr_reader :compensation_job_ids
      end

      # Normalizes operator rollback reasons for public workflow inspection.
      class Reason
        def initialize(reason)
          @reason = reason
        end

        def normalize
          Karya::Internal::DeadLetterReason.normalize(reason, error_class: InvalidExecutionError)
        rescue InvalidExecutionError => e
          raise InvalidExecutionError, e.message.sub('dead_letter_reason', 'reason'), cause: e
        end

        private

        attr_reader :reason
      end

      private_constant :CompensationJobIds, :Reason, :Timestamp
    end
  end
end
