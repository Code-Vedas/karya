# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    # Immutable result for one in-flight recovery pass.
    class RecoveryReport
      attr_reader :expired_jobs, :recovered_at, :recovered_reserved_jobs, :recovered_running_jobs

      # Validates and freezes one recovery report job group.
      class JobGroup
        def initialize(name, jobs)
          @name = name
          @jobs = jobs
        end

        def to_a
          raise InvalidQueueStoreOperationError, "#{name} must be an Array" unless jobs.is_a?(Array)

          jobs.each do |job|
            raise InvalidQueueStoreOperationError, "#{name} entries must be Karya::Job" unless job.is_a?(Job)
          end

          jobs.dup.freeze
        end

        private

        attr_reader :jobs, :name
      end

      def initialize(recovered_at:, expired_jobs:, recovered_reserved_jobs:, recovered_running_jobs:)
        raise InvalidQueueStoreOperationError, 'recovered_at must be a Time' unless recovered_at.is_a?(Time)

        @recovered_at = recovered_at.dup.freeze
        @expired_jobs = JobGroup.new(:expired_jobs, expired_jobs).to_a
        @recovered_reserved_jobs = JobGroup.new(:recovered_reserved_jobs, recovered_reserved_jobs).to_a
        @recovered_running_jobs = JobGroup.new(:recovered_running_jobs, recovered_running_jobs).to_a

        freeze
      end

      def jobs
        expired_jobs + recovered_reserved_jobs + recovered_running_jobs
      end

      def recovered_jobs
        recovered_reserved_jobs + recovered_running_jobs
      end

      private_constant :JobGroup
    end
  end
end
