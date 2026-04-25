# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Workflow
    # Immutable identity and membership for one runtime workflow batch.
    class Batch
      DEFAULT_MAX_SIZE = 1000

      attr_reader :created_at, :id, :job_ids, :updated_at

      def initialize(id:, job_ids:, created_at:, updated_at: created_at, max_size: DEFAULT_MAX_SIZE)
        @id = Workflow.send(:normalize_batch_identifier, :batch_id, id)
        @job_ids = JobIdList.new(job_ids, max_size:).to_a
        @created_at = Timestamp.new(:created_at, created_at).to_time
        @updated_at = Timestamp.new(:updated_at, updated_at).to_time
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

          raise InvalidBatchError, "#{name} must be a Time"
        end

        private

        attr_reader :name, :value
      end

      # Normalizes a batch membership list without interning request input.
      class JobIdList
        def initialize(job_ids, max_size:)
          @job_ids = job_ids
          @max_size = max_size
        end

        def to_a
          raise InvalidBatchError, 'job_ids must be an Array' unless job_ids.is_a?(Array)
          raise InvalidBatchError, 'batch must include at least one job' if job_ids.empty?
          raise InvalidBatchError, 'max_size must be a positive Integer' unless max_size.is_a?(Integer) && max_size.positive?

          normalized_job_ids = job_ids.map do |job_id|
            Workflow.send(:normalize_batch_identifier, :job_id, job_id)
          end
          validate_size(normalized_job_ids)
          validate_unique(normalized_job_ids)
          normalized_job_ids.freeze
        end

        private

        attr_reader :job_ids, :max_size

        def validate_size(normalized_job_ids)
          return if normalized_job_ids.length <= max_size

          raise InvalidBatchError, "batch size must be at most #{max_size} #{job_label}"
        end

        def job_label
          max_size == 1 ? 'job' : 'jobs'
        end

        def validate_unique(normalized_job_ids)
          duplicate_job_id = normalized_job_ids.tally.find { |_job_id, count| count > 1 }&.first
          raise InvalidBatchError, "duplicate batch job id #{duplicate_job_id.inspect}" if duplicate_job_id
        end
      end

      private_constant :DEFAULT_MAX_SIZE, :JobIdList, :Timestamp
    end
  end
end
