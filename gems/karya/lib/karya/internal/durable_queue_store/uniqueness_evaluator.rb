# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Evaluates idempotency and uniqueness directly from durable rows.
      class UniquenessEvaluator
        UNIQUENESS_SCOPES = %i[queued active until_terminal].freeze
        private_constant :UNIQUENESS_SCOPES

        # Builds job domain objects directly from durable job rows.
        class RowDecoder
          def initialize(row:, job_id:)
            @row = row
            @job_id = job_id
          end

          def build_job
            Job.new(**attributes)
          end

          def attributes
            scalar_attributes.merge(payload_attributes)
          end

          private

          attr_reader :job_id, :row

          def scalar_attributes
            base_attributes.merge(lifecycle_attributes).merge(uniqueness_attributes)
          end

          def base_attributes
            {
              id: job_id,
              queue: row.fetch(:queue),
              handler: row.fetch(:handler),
              arguments: PayloadCodec.decode(row.fetch(:arguments_payload)),
              created_at: row.fetch(:created_at),
              updated_at: row.fetch(:updated_at)
            }
          end

          def lifecycle_attributes
            {
              priority: row.fetch(:priority),
              state: row.fetch(:state),
              attempt: row.fetch(:attempt),
              next_retry_at: next_retry_at,
              execution_timeout: row[:execution_timeout_seconds],
              expires_at: row[:expires_at],
              failure_classification: row[:failure_classification],
              dead_letter_reason: row[:dead_letter_reason],
              dead_lettered_at: row[:dead_lettered_at],
              dead_letter_source_state: row[:dead_letter_source_state]
            }
          end

          def uniqueness_attributes
            {
              idempotency_key: row[:idempotency_key],
              uniqueness_key: row[:uniqueness_key],
              uniqueness_scope: row[:uniqueness_scope]
            }
          end

          def payload_attributes
            {
              retry_policy: decode_optional_payload(:retry_policy_payload),
              concurrency_scope: decode_optional_payload(:concurrency_scope),
              rate_limit_scope: decode_optional_payload(:rate_limit_scope)
            }
          end

          def decode_optional_payload(payload_key)
            payload = row[payload_key]
            payload && PayloadCodec.decode(payload)
          end

          def next_retry_at
            row[:state].to_sym == :retry_pending ? row[:visible_at] : nil
          end
        end

        # Builds reservation snapshots grouped by durable lease phase.
        class ReservationIndex
          # Builds one reservation snapshot from a durable reservation row.
          class ReservationBuilder
            def initialize(row:, job:)
              @row = row
              @job = job
            end

            def build
              job_id, token, worker_id, reserved_at, expires_at = row.values_at(
                :job_id,
                :reservation_token,
                :worker_id,
                :reserved_at,
                :lease_expires_at
              )
              Reservation.new(
                token: token,
                job_id:,
                queue: row.fetch(:queue, job.queue),
                worker_id:,
                reserved_at:,
                expires_at:
              )
            end

            private

            attr_reader :job, :row
          end

          def initialize(rows:, jobs_by_id:)
            @rows = rows
            @jobs_by_id = jobs_by_id
          end

          def build
            grouped = { reserved: [], running: [] }
            Array(rows).each do |row|
              phase = row.fetch(:phase).to_sym
              next unless grouped.key?(phase)

              grouped[phase] << reservation_from(row)
            end
            grouped.freeze
          end

          private

          attr_reader :jobs_by_id, :rows

          def reservation_from(row)
            ReservationBuilder.new(row:, job: jobs_by_id.fetch(row.fetch(:job_id))).build
          end
        end

        def initialize(rows:, now:)
          @rows = rows
          @now = now
        end

        def decision_for(job:)
          jobs_index = jobs_by_id
          duplicate_job = jobs_index[job.id]
          if duplicate_job
            return rejection_for(
              job:,
              result: :duplicate_job_id,
              key_type: :job_id,
              key: job.id,
              conflicting_job_id: duplicate_job.id
            )
          end
          idempotency_duplicate = duplicate_idempotency_job(job)
          if idempotency_duplicate
            return rejection_for(
              job:,
              result: :duplicate_idempotency_key,
              key_type: :idempotency_key,
              key: job.idempotency_key,
              conflicting_job_id: idempotency_duplicate.id
            )
          end
          uniqueness_duplicate = duplicate_uniqueness_job(job)
          if uniqueness_duplicate
            return rejection_for(
              job:,
              result: :duplicate_uniqueness_key,
              key_type: :uniqueness_key,
              key: job.uniqueness_key,
              conflicting_job_id: uniqueness_duplicate.id
            )
          end
          {
            captured_at: now.dup.freeze,
            job_id: job.id,
            action: :accept,
            result: :accepted,
            key_type: nil,
            key: nil,
            conflicting_job_id: nil,
            uniqueness_scope: job.uniqueness_scope
          }.freeze
        end

        def snapshot
          {
            captured_at: now.dup.freeze,
            idempotency_keys: snapshot_idempotency_keys,
            uniqueness_keys: snapshot_uniqueness_keys
          }.freeze
        end

        def raise_duplicate_enqueue_error(decision)
          action, result, job_id, key = decision.values_at(:action, :result, :job_id, :key)
          return unless action == :reject

          inspected_job_id = job_id.inspect
          case result
          when :duplicate_job_id
            raise DuplicateJobError, "job #{inspected_job_id} is already present in the queue store"
          when :duplicate_idempotency_key
            raise DuplicateIdempotencyKeyError,
                  "job #{inspected_job_id} conflicts with idempotency_key #{DuplicateKeySummary.new(key)}"
          when :duplicate_uniqueness_key
            raise DuplicateUniquenessKeyError,
                  "job #{inspected_job_id} conflicts with uniqueness_key #{DuplicateKeySummary.new(key)}"
          end
        end

        private

        attr_reader :now, :rows

        def rejection_for(job:, result:, key_type:, key:, conflicting_job_id:)
          {
            captured_at: now.dup.freeze,
            job_id: job.id,
            action: :reject,
            result:,
            key_type:,
            key:,
            conflicting_job_id:,
            uniqueness_scope: job.uniqueness_scope
          }.freeze
        end

        def duplicate_idempotency_job(job, exclude_job_id: nil)
          return nil unless job.idempotency_key

          jobs_by_id.each_value do |existing_job|
            next if skipped_job_id?(job, existing_job.id, exclude_job_id)
            return existing_job if existing_job.idempotency_key == job.idempotency_key
          end

          nil
        end

        def duplicate_uniqueness_job(job, exclude_job_id: nil)
          return nil unless job.uniqueness_key

          jobs_by_id.each_value do |existing_job|
            next if skipped_job_id?(job, existing_job.id, exclude_job_id)
            next unless existing_job.uniqueness_key == job.uniqueness_key

            effective_existing_job = effective_uniqueness_job(existing_job)
            next unless effective_existing_job&.uniqueness_scope
            next unless job.uniqueness_scope
            return effective_existing_job if uniqueness_conflict_between?(effective_existing_job, job)
          end

          nil
        end

        def skipped_job_id?(job, existing_job_id, exclude_job_id) = existing_job_id == job.id || existing_job_id == exclude_job_id

        def snapshot_idempotency_keys
          jobs_by_id.each_value.with_object({}) do |job, snapshot|
            idempotency_key = job.idempotency_key
            next unless idempotency_key

            snapshot[idempotency_key] = {
              key: idempotency_key,
              job_id: job.id,
              queue: job.queue,
              handler: job.handler,
              state: job.state,
              created_at: job.created_at,
              updated_at: job.updated_at
            }.freeze
          end.freeze
        end

        def snapshot_uniqueness_keys
          jobs_by_id.each_value.with_object({}) do |job, snapshot|
            uniqueness_key = job.uniqueness_key
            next unless uniqueness_key

            effective_job = effective_uniqueness_job(job)
            next unless effective_job&.uniqueness_scope

            blocked_scopes = blocked_incoming_scopes(effective_job)
            next if blocked_scopes.empty?

            blockers = snapshot[uniqueness_key] ||= []
            blockers << {
              key: uniqueness_key,
              job_id: job.id,
              queue: job.queue,
              handler: job.handler,
              state: job.state,
              effective_state: effective_job.state,
              uniqueness_scope: effective_job.uniqueness_scope,
              blocked_incoming_scopes: blocked_scopes
            }.freeze
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

        def incoming_uniqueness_state(job) = (state = job.state) == :submission ? :queued : state

        def effective_uniqueness_job(job)
          case job.state
          when :queued
            job_expired?(job) ? nil : job
          when :retry_pending
            effective_retry_pending_uniqueness_job(job)
          when :reserved
            effective_reserved_uniqueness_job(job)
          when :running
            effective_running_uniqueness_job(job)
          else
            job
          end
        end

        def effective_retry_pending_uniqueness_job(job)
          return nil if job_expired?(job)

          next_retry_at = job.next_retry_at
          return job unless next_retry_at && next_retry_at <= now

          job.transition_to(:queued, updated_at: now, next_retry_at: nil, failure_classification: nil)
        end

        def effective_reserved_uniqueness_job(job)
          return nil if job_expired?(job)
          return job unless lease_expired_for_uniqueness?(job.id, :reserved)

          job.transition_to(:queued, updated_at: now, failure_classification: nil)
        end

        def effective_running_uniqueness_job(job)
          return job unless lease_expired_for_uniqueness?(job.id, :running)

          job.transition_to(:queued, updated_at: now)
        end

        def job_expired?(job) = (expires_at = job.expires_at) && expires_at <= now

        def lease_expired_for_uniqueness?(job_id, phase)
          reservations_by_phase.fetch(phase).any? do |reservation|
            reservation.job_id == job_id && reservation.expired?(now)
          end
        end

        def reservations_by_phase
          @reservations_by_phase ||= ReservationIndex.new(rows: rows[:reservations], jobs_by_id:).build
        end

        def jobs_by_id
          @jobs_by_id ||= Array(rows[:jobs]).each_with_object({}) do |row, jobs|
            job_id = row.fetch(:job_id)
            jobs[job_id] = RowDecoder.new(row:, job_id:).build_job
          end.freeze
        end
      end
    end
  end
end
