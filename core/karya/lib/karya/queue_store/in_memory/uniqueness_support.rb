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
        # Compact duplicate-key log formatting that avoids dumping arbitrarily long keys.
        class DuplicateKeySummary
          MAX_PREVIEW_LENGTH = 64

          def initialize(key)
            @key = key
          end

          def to_s
            "#{preview.inspect} (length=#{key.length})"
          end

          private

          attr_reader :key

          def preview
            return key unless key.length > MAX_PREVIEW_LENGTH

            "#{key[0, MAX_PREVIEW_LENGTH]}..."
          end
        end

        # Frozen inspectable result for a candidate enqueue.
        class Decision
          def initialize(job:, now:)
            @captured_at = now.dup.freeze
            @job_id = job.id
            @uniqueness_scope = job.uniqueness_scope
          end

          def accept
            to_h(
              action: :accept,
              result: :accepted,
              key_type: nil,
              key: nil,
              conflicting_job_id: nil
            )
          end

          def reject(result:, key_type:, key:, conflicting_job_id:)
            to_h(action: :reject, result:, key_type:, key:, conflicting_job_id:)
          end

          private

          def to_h(action:, result:, key_type:, key:, conflicting_job_id:)
            {
              captured_at: @captured_at,
              job_id: @job_id,
              action:,
              result:,
              key_type:,
              key:,
              conflicting_job_id:,
              uniqueness_scope: @uniqueness_scope
            }.freeze
          end
        end

        # Frozen snapshot entry for one idempotency key owner.
        class IdempotencyKeySnapshot
          def initialize(job:, key:)
            @key = key
            @job_id = job.id
            @queue = job.queue
            @handler = job.handler
            @state = job.state
            @created_at = job.created_at
            @updated_at = job.updated_at
          end

          def to_h
            {
              key: @key,
              job_id: @job_id,
              queue: @queue,
              handler: @handler,
              state: @state,
              created_at: @created_at,
              updated_at: @updated_at
            }.freeze
          end
        end

        # Frozen snapshot entry for one effective uniqueness blocker.
        class UniquenessKeySnapshot
          def initialize(job:, effective_job:, key:, blocked_scopes:)
            @key = key
            @job_id = job.id
            @queue = job.queue
            @handler = job.handler
            @state = job.state
            @effective_state = effective_job.state
            @uniqueness_scope = effective_job.uniqueness_scope
            @blocked_incoming_scopes = blocked_scopes
          end

          def to_h
            {
              key: @key,
              job_id: @job_id,
              queue: @queue,
              handler: @handler,
              state: @state,
              effective_state: @effective_state,
              uniqueness_scope: @uniqueness_scope,
              blocked_incoming_scopes: @blocked_incoming_scopes
            }.freeze
          end
        end

        # Finds an existing job matching a candidate key and caller-supplied predicate.
        class DuplicateSearch
          def initialize(jobs_by_id:, job:, key:, key_name:, exclude_job_id:)
            @jobs_by_id = jobs_by_id
            @job_id = job.id
            @key = key
            @key_name = key_name
            @exclude_job_id = exclude_job_id
            @skipped_job_ids = [@exclude_job_id, @job_id]
          end

          def call
            return nil unless @key

            @jobs_by_id.each_value do |existing_job|
              existing_job_id = existing_job.id
              next if skip_job_id?(existing_job_id)
              next unless existing_job.public_send(@key_name) == @key
              return existing_job if yield(existing_job)
            end

            nil
          end

          private

          def skip_job_id?(existing_job_id)
            @skipped_job_ids.include?(existing_job_id)
          end
        end

        private_constant :Decision, :DuplicateKeySummary, :DuplicateSearch, :IdempotencyKeySnapshot, :UniquenessKeySnapshot

        private

        UNIQUENESS_SCOPES = %i[queued active until_terminal].freeze
        private_constant :UNIQUENESS_SCOPES

        def store_job(job:)
          job_id = job.id
          job_state = job.state
          state.jobs_by_id[job_id] = job
          clear_stuck_job_recovery(job_id) if JobLifecycle.terminal?(job_state) || job_state == :dead_letter
          job
        end

        def build_uniqueness_decision(job, now)
          duplicate_job = duplicate_job_id(job)
          if duplicate_job
            return Decision.new(job:, now:).reject(
              result: :duplicate_job_id,
              key_type: :job_id,
              key: job.id,
              conflicting_job_id: duplicate_job.id
            ).to_h
          end

          idempotency_duplicate = duplicate_idempotency_job(job)
          if idempotency_duplicate
            return Decision.new(job:, now:).reject(
              result: :duplicate_idempotency_key,
              key_type: :idempotency_key,
              key: job.idempotency_key,
              conflicting_job_id: idempotency_duplicate.id
            ).to_h
          end

          uniqueness_duplicate = duplicate_uniqueness_job(job, now)
          if uniqueness_duplicate
            return Decision.new(job:, now:).reject(
              result: :duplicate_uniqueness_key,
              key_type: :uniqueness_key,
              key: job.uniqueness_key,
              conflicting_job_id: uniqueness_duplicate.id
            ).to_h
          end

          Decision.new(job:, now:).accept
        end

        def duplicate_job_id(job)
          state.jobs_by_id[job.id]
        end

        def duplicate_idempotency_job(job, exclude_job_id: nil)
          duplicate_search(job, key: job.idempotency_key, key_name: :idempotency_key, exclude_job_id:).call { true }
        end

        def duplicate_uniqueness_job(job, now, exclude_job_id: nil)
          duplicate_search(
            job,
            key: job.uniqueness_key,
            key_name: :uniqueness_key,
            exclude_job_id:
          ).call do |existing_job|
            effective_existing_job = effective_uniqueness_job(existing_job, now)
            next false unless effective_existing_job
            next false unless effective_existing_job.uniqueness_scope && job.uniqueness_scope

            uniqueness_conflict_between?(effective_existing_job, job)
          end
        end

        def duplicate_search(job, key:, key_name:, exclude_job_id:)
          DuplicateSearch.new(jobs_by_id: state.jobs_by_id, job:, key:, key_name:, exclude_job_id:)
        end

        def build_uniqueness_snapshot(now)
          {
            captured_at: now.dup.freeze,
            idempotency_keys: snapshot_idempotency_keys,
            uniqueness_keys: snapshot_uniqueness_keys(now)
          }.freeze
        end

        def snapshot_idempotency_keys
          state.jobs_by_id.each_value.with_object({}) do |job, snapshot|
            idempotency_key = job.idempotency_key
            next unless idempotency_key

            snapshot[idempotency_key] = IdempotencyKeySnapshot.new(job:, key: idempotency_key).to_h
          end.freeze
        end

        def snapshot_uniqueness_keys(now)
          state.jobs_by_id.each_value.with_object({}) do |job, snapshot|
            uniqueness_key = job.uniqueness_key
            next unless uniqueness_key

            effective_job = effective_uniqueness_job(job, now)
            next unless effective_job&.uniqueness_scope

            blocked_scopes = blocked_incoming_scopes(effective_job)
            next if blocked_scopes.empty?

            blockers = snapshot[uniqueness_key] ||= []
            blockers << UniquenessKeySnapshot.new(job:, effective_job:, key: uniqueness_key, blocked_scopes:).to_h
          end.transform_values!(&:freeze).freeze
        end

        def blocked_incoming_scopes(existing_job)
          UNIQUENESS_SCOPES.select { |incoming_scope| uniqueness_scope_conflicts?(existing_job, incoming_scope) }.freeze
        end

        def uniqueness_scope_conflicts?(existing_job, incoming_scope)
          existing_state = existing_job.state
          incoming_state = :queued
          existing_scope = existing_job.uniqueness_scope
          incoming_currently_blocks = uniqueness_scope_blocks_state?(incoming_scope, incoming_state)
          existing_currently_blocks = uniqueness_scope_blocks_state?(existing_scope, existing_state)

          (incoming_currently_blocks && uniqueness_scope_blocks_state?(incoming_scope, existing_state)) ||
            (existing_currently_blocks && uniqueness_scope_blocks_state?(existing_scope, incoming_state))
        end

        def uniqueness_conflict?(job, exclude_job_id: nil, now: nil)
          !!duplicate_uniqueness_job(job, now, exclude_job_id:)
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

        def uniqueness_scope_blocks_state?(scope, state)
          case scope
          when :queued
            %i[queued retry_pending].include?(state)
          when :active
            %i[queued reserved running retry_pending].include?(state)
          when :until_terminal
            !JobLifecycle.terminal?(state)
          else
            false
          end
        end

        def incoming_uniqueness_state(job)
          state_name = job.state
          state_name == :submission ? :queued : state_name
        end

        def effective_uniqueness_job(job, now)
          return job unless now

          state_name = job.state

          case state_name
          when :queued
            effective_queued_uniqueness_job(job, now)
          when :retry_pending
            effective_retry_pending_uniqueness_job(job, now)
          when :reserved
            effective_reserved_uniqueness_job(job, now)
          when :running
            effective_running_uniqueness_job(job, now)
          else
            job
          end
        end

        def effective_queued_uniqueness_job(job, now)
          job_expired?(job, now) ? nil : job
        end

        def effective_retry_pending_uniqueness_job(job, now)
          expired = job_expired?(job, now)
          return nil if expired

          next_retry_at = job.next_retry_at
          return job unless next_retry_at && next_retry_at <= now

          job.transition_to(:queued, updated_at: now, next_retry_at: nil, failure_classification: nil)
        end

        def effective_reserved_uniqueness_job(job, now)
          return nil if job_expired?(job, now)
          return job unless lease_expired_for_uniqueness?(state.reservations_by_token, job.id, now)

          job.transition_to(:queued, updated_at: now, failure_classification: nil)
        end

        def effective_running_uniqueness_job(job, now)
          return job unless lease_expired_for_uniqueness?(state.executions_by_token, job.id, now)

          ExecutionRecovery.new(job, now).to_queued_job
        end

        def lease_expired_for_uniqueness?(leases_by_token, job_id, now)
          leases_by_token.each_value.any? do |lease|
            lease_job_id = lease.job_id
            lease_job_id == job_id && lease.expired?(now)
          end
        end

        def resolve_reentry_uniqueness(job, now: nil)
          return job unless uniqueness_scope_blocks_state?(job.uniqueness_scope, job.state)
          return job unless uniqueness_conflict?(job, exclude_job_id: job.id, now:)

          reentry_conflict_job(job)
        end

        def resolve_reentry_and_store(job, now: nil)
          store_and_requeue_if_needed(resolve_reentry_uniqueness(job, now:))
        end

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

        def raise_duplicate_enqueue_error(duplicate_decision)
          job_id = duplicate_decision.fetch(:job_id)
          key = duplicate_decision.fetch(:key)
          case duplicate_decision.fetch(:result)
          when :duplicate_job_id
            raise DuplicateJobError, "job #{job_id.inspect} is already present in the queue store"
          when :duplicate_idempotency_key
            raise_duplicate_idempotency_key_error(job_id:, idempotency_key: key)
          when :duplicate_uniqueness_key
            raise_duplicate_uniqueness_key_error(job_id:, uniqueness_key: key)
          end
        end

        def raise_duplicate_uniqueness_key_error(job_id:, uniqueness_key:)
          raise DuplicateUniquenessKeyError,
                "job #{job_id.inspect} conflicts with uniqueness_key #{DuplicateKeySummary.new(uniqueness_key)}"
        end

        def raise_duplicate_idempotency_key_error(job_id:, idempotency_key:)
          raise DuplicateIdempotencyKeyError,
                "job #{job_id.inspect} conflicts with idempotency_key #{DuplicateKeySummary.new(idempotency_key)}"
        end
      end
    end
  end
end
