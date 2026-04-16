# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      # Idempotency and uniqueness checks over canonical stored jobs.
      module UniquenessSupport
        UNIQUENESS_REENTRY_FAILURE_CLASSIFICATION = :error
        UNIQUENESS_TERMINAL_STATES = %i[succeeded cancelled failed].freeze

        private

        def store_job(job:)
          state.jobs_by_id[job.id] = job
          job
        end

        def uniqueness_conflict?(job, exclude_job_id: nil)
          duplicate_exists_for?(job, key: job.uniqueness_key, exclude_job_id:) do |existing_job, candidate_job|
            next false unless existing_job.uniqueness_key == candidate_job.uniqueness_key
            next false unless existing_job.uniqueness_scope && candidate_job.uniqueness_scope

            uniqueness_conflict_between?(existing_job, candidate_job)
          end
        end

        def idempotency_conflict?(job, exclude_job_id: nil)
          duplicate_exists_for?(job, key: job.idempotency_key, exclude_job_id:) do |existing_job, candidate_job|
            next false unless existing_job.idempotency_key == candidate_job.idempotency_key

            true
          end
        end

        def uniqueness_conflict_between?(existing_job, incoming_job)
          incoming_state = incoming_uniqueness_state(incoming_job)
          existing_state = existing_job.state
          incoming_scope = incoming_job.uniqueness_scope
          existing_scope = existing_job.uniqueness_scope
          incoming_currently_blocks = uniqueness_scope_blocks_state?(incoming_scope, incoming_state)
          existing_currently_blocks = uniqueness_scope_blocks_state?(existing_scope, existing_state)

          (incoming_currently_blocks && uniqueness_scope_blocks_state?(incoming_scope, existing_state)) ||
            (existing_currently_blocks && uniqueness_scope_blocks_state?(existing_scope, incoming_state))
        end

        # :reek:UtilityFunction
        def uniqueness_scope_blocks_state?(scope, state)
          case scope
          when :queued
            %i[queued retry_pending].include?(state)
          when :active
            %i[queued reserved running retry_pending].include?(state)
          when :until_terminal
            !UNIQUENESS_TERMINAL_STATES.include?(state)
          else
            false
          end
        end

        # :reek:UtilityFunction
        def incoming_uniqueness_state(job)
          state_name = job.state
          state_name == :submission ? :queued : state_name
        end

        # :reek:FeatureEnvy
        def duplicate_exists_for?(job, key:, exclude_job_id:)
          return false unless key

          jobs_by_id = state.jobs_by_id
          jobs_by_id.each_value do |existing_job|
            existing_job_id = existing_job.id
            next if existing_job_id == exclude_job_id || existing_job_id == job.id
            return true if yield(existing_job, job)
          end

          false
        end

        def resolve_reentry_uniqueness(job)
          return job unless uniqueness_scope_blocks_state?(job.uniqueness_scope, job.state)
          return job unless uniqueness_conflict?(job, exclude_job_id: job.id)

          reentry_conflict_job(job)
        end

        # :reek:UtilityFunction
        def reentry_conflict_job(job)
          updated_at = job.updated_at
          if job.can_transition_to?(:failed)
            return job.transition_to(
              :failed,
              updated_at:,
              next_retry_at: nil,
              failure_classification: UNIQUENESS_REENTRY_FAILURE_CLASSIFICATION
            )
          end

          job.transition_to(:cancelled, updated_at:, next_retry_at: nil, failure_classification: nil)
        end

        def raise_duplicate_uniqueness_key_error(job_id:, uniqueness_key:)
          raise DuplicateUniquenessKeyError,
                "job #{job_id.inspect} conflicts with uniqueness_key #{uniqueness_key.inspect}"
        end

        def raise_duplicate_idempotency_key_error(job_id:, idempotency_key:)
          raise DuplicateIdempotencyKeyError,
                "job #{job_id.inspect} conflicts with idempotency_key #{idempotency_key.inspect}"
        end
      end
    end
  end
end
