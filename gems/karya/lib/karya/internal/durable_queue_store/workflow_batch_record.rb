# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Builds one durable workflow-batch row from registration and batch state.
      class WorkflowBatchRecord
        FAILED_STATES = %i[failed dead_letter].freeze
        # Computes aggregate workflow batch state from member jobs.
        class AggregateState
          def initialize(jobs)
            @jobs = jobs
          end

          def to_sym
            state_count = job_states.length
            return :failed if job_states.any? { |state| FAILED_STATES.include?(state) }
            return :running if jobs.any? { |job| !job.terminal? }
            return :succeeded if job_states == Array.new(state_count, :succeeded)
            return :cancelled if job_states == Array.new(state_count, :cancelled)

            :completed
          end

          private

          attr_reader :jobs

          def job_states
            @job_states ||= jobs.map(&:state)
          end
        end
        private_constant :AggregateState

        def initialize(namespace:, batch:, registration:, jobs_by_id:)
          @namespace = namespace
          @batch = batch
          @registration = registration
          @jobs_by_id = jobs_by_id
        end

        def to_h
          {
            namespace:,
            batch_id: batch.id,
            workflow_id: registration.workflow_id,
            workflow_family: registration.workflow_family,
            workflow_version: registration.workflow_version,
            state: workflow_state.to_s,
            created_at: batch.created_at,
            updated_at: batch.updated_at
          }
        end

        private

        attr_reader :batch, :jobs_by_id, :namespace, :registration

        def jobs
          @jobs ||= batch.job_ids.map { |job_id| jobs_by_id.fetch(job_id) }
        end

        def workflow_state
          AggregateState.new(jobs).to_sym
        end
      end
    end
  end
end
