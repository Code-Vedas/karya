# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      # Idempotency and uniqueness index helpers.
      module UniquenessSupport
        private

        # :reek:FeatureEnvy
        def store_job(job:)
          job_id = job.id
          state.jobs_by_id[job_id] = job
          synchronize_idempotency_state(job_id:, idempotency_key: job.idempotency_key)
          synchronize_uniqueness_state(
            job_id:,
            uniqueness_key: job.uniqueness_key,
            uniqueness_scope: job.uniqueness_scope,
            state_name: job.state,
            terminal: job.terminal?
          )
          job
        end

        def synchronize_idempotency_state(job_id:, idempotency_key:)
          return unless idempotency_key

          state.register_idempotency_job(idempotency_key, job_id)
        end

        def synchronize_uniqueness_state(job_id:, uniqueness_key:, uniqueness_scope:, state_name:, terminal:)
          return unless uniqueness_key

          blocks_uniqueness =
            case uniqueness_scope
            when :queued
              %i[queued retry_pending].include?(state_name)
            when :active
              %i[queued reserved running retry_pending].include?(state_name)
            when :until_terminal
              !terminal
            else
              false
            end

          if blocks_uniqueness
            state.register_uniqueness_job(uniqueness_key, job_id)
          else
            state.delete_uniqueness_job(uniqueness_key, job_id)
          end
        end

        def uniqueness_conflict?(job)
          uniqueness_key = job.uniqueness_key
          return false unless uniqueness_key

          uniqueness_job_id_by_key = state.uniqueness_job_id_by_key
          duplicate_job_id = uniqueness_job_id_by_key[uniqueness_key]
          return false unless duplicate_job_id

          duplicate_job = state.jobs_by_id[duplicate_job_id]
          unless duplicate_job
            uniqueness_job_id_by_key.delete(uniqueness_key)
            return false
          end

          duplicate_job_state = duplicate_job.state
          duplicate_blocks_uniqueness =
            case duplicate_job.uniqueness_scope
            when :queued
              %i[queued retry_pending].include?(duplicate_job_state)
            when :active
              %i[queued reserved running retry_pending].include?(duplicate_job_state)
            when :until_terminal
              !duplicate_job.terminal?
            else
              false
            end
          return true if duplicate_blocks_uniqueness

          state.delete_uniqueness_job(uniqueness_key, duplicate_job_id)
          false
        end

        def idempotency_conflict?(job)
          idempotency_key = job.idempotency_key
          return false unless idempotency_key

          idempotency_job_id_by_key = state.idempotency_job_id_by_key
          duplicate_job_id = idempotency_job_id_by_key[idempotency_key]
          return false unless duplicate_job_id

          duplicate_job = state.jobs_by_id[duplicate_job_id]
          unless duplicate_job
            idempotency_job_id_by_key.delete(idempotency_key)
            return false
          end

          true
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
