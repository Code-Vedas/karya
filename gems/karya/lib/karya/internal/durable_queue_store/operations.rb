# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Placeholder durable operations for the row-native rebuild.
      module Operations
        # Shared row-to-domain mapping and normalized row-query helpers.
        module RowSupport
          include WorkflowRuntimeSupport

          BATCH_PLACEHOLDER_WORKFLOW_ID = '__batch__'
          QUEUED_STATES = %i[queued retry_pending].freeze
          private_constant :BATCH_PLACEHOLDER_WORKFLOW_ID

          private

          def find_reservation_row(reservation_rows, reservation_token)
            normalized_token = normalize_identifier(:reservation_token, reservation_token, error_class: InvalidQueueStoreOperationError)
            reservation_rows.find { |row| row.fetch(:reservation_token) == normalized_token }
          end
        end

        # Shared helpers for bulk job mutations that report changed and skipped jobs.
        module BulkMutationSupport
          private

          def normalize_job_ids(job_ids)
            raise InvalidQueueStoreOperationError, 'job_ids must be an Array' unless job_ids.is_a?(Array)

            job_ids.map do |job_id|
              normalize_identifier(:job_id, job_id, error_class: InvalidQueueStoreOperationError)
            end
          end

          def report_for(action:, job_ids:, now:, &)
            Karya::Internal::BulkMutation::ReportBuilder.new(
              action:,
              job_ids:,
              now:
            ).to_report(&)
          end

          def bulk_mutation_result(context, action:, job_ids:, now:, &mutation)
            BulkMutationRunner.new(context:, action:, job_ids:, now:, host: self, &mutation).call
          end

          def uniqueness_conflict?(job, rows, now:, exclude_job_id:)
            evaluator = UniquenessEvaluator.new(rows:, now:)
            !evaluator.send(:duplicate_uniqueness_job, job, exclude_job_id:).nil?
          end

          def update_rows_with_job(rows, job_id, replacement_job)
            rows.merge(
              jobs: rows.fetch(:jobs).map do |row|
                row.fetch(:job_id) == job_id ? JobRecord.new(namespace: rows.fetch(:namespace), job: replacement_job).to_h : row
              end
            )
          end

          def storeable_plan_for_job(context, rows, job, delete_queue_entries: true, delete_reservations: true)
            workflow_rows = rows.merge(namespace: context.namespace)
            runtime_rows = JobRuntimeRows.new(namespace: context.namespace, rows:)
            deletes = runtime_rows.deletes_for(job_id: job.id, delete_queue_entries:, delete_reservations:)
            inserts = runtime_rows.queue_entry_insert_groups_for(job)
            workflow_updates = workflow_row_updates_for_job(context, workflow_rows, job)
            workflow_history_rows = workflow_history_rows_for_job(workflow_rows, namespace: context.namespace, replacement_job: job)

            MutationPlan.new(
              updates: {
                jobs: [JobRecord.new(namespace: context.namespace, job:).to_h],
                workflow_steps: workflow_updates.fetch(:workflow_steps),
                workflow_batches: workflow_updates.fetch(:workflow_batches)
              },
              inserts: inserts.merge(workflow_history: workflow_history_rows),
              deletes:
            )
          end
        end

        # Shared helpers for recovering expired jobs and lease-backed work.
        module RecoverySupport
          COUNTED_FAILURE_CLASSIFICATIONS = %i[error timeout].freeze
          STUCK_JOB_RECOVERY_REASON = 'running_lease_expired'

          private

          def expiration_time(request)
            normalize_time(:now, request.fetch(:now), error_class: InvalidQueueStoreOperationError)
          end

          def job_expired?(job, now)
            expires_at = job.expires_at
            expires_at && expires_at <= now
          end

          def recover_expired_reservation(job, now)
            job.transition_to(:queued, updated_at: now, failure_classification: nil)
          end

          def recover_expired_execution(job, now)
            job.transition_to(:queued, updated_at: now, failure_classification: nil)
          end

          def expire_job(job, now)
            job.expire(updated_at: now)
          end
        end

        # Shared policy-state transitions for circuit breakers and stuck-job tracking.
        module ReliabilityPolicySupport
          CLOSED_BREAKER_STATE = { state: :closed, cooldown_until: nil }.freeze
          COUNTED_FAILURE_CLASSIFICATIONS = %i[error timeout].freeze
          STUCK_JOB_RECOVERY_REASON = 'running_lease_expired'

          private

          def policy_rows_by_kind(rows)
            rows.fetch(:policy_state, []).group_by { |row| row.fetch(:policy_kind) }
          end

          def policy_scope_key(row)
            kind = row.fetch(:scope_kind)
            value = row.fetch(:scope_value)
            return '' if kind == 'queue' && value.empty?

            "#{kind}:#{value}"
          end

          def breaker_state_row(rows, scope_key)
            row_for_policy_kind(rows, 'breaker_state', scope_key)
          end

          def breaker_failures_row(rows, scope_key)
            row_for_policy_kind(rows, 'breaker_failures', scope_key)
          end

          def half_open_probe_row(rows, scope_key)
            row_for_policy_kind(rows, 'half_open_probes', scope_key)
          end

          def stuck_job_recovery_row(rows, job_id)
            row_for_policy_kind(rows, 'stuck_job_recovery', "job:#{job_id}")
          end

          def row_for_policy_kind(rows, policy_kind, scope_key)
            rows.fetch(:policy_state, []).find do |row|
              row.fetch(:policy_kind) == policy_kind && policy_scope_key(row) == scope_key
            end
          end

          def breaker_failures(rows, scope_key, now, policy)
            payload = PolicyStateRow.new(row: breaker_failures_row(rows, scope_key)).payload
            Array(payload['timestamps'] || payload[:timestamps]).select { |timestamp| timestamp > now - policy.window }
          end

          def breaker_state(rows, scope_key, now, _policy)
            payload = PolicyStateRow.new(row: breaker_state_row(rows, scope_key)).payload
            state = (payload['state'] || payload[:state] || CLOSED_BREAKER_STATE.fetch(:state)).to_sym
            cooldown_until = payload['cooldown_until'] || payload[:cooldown_until]
            return CLOSED_BREAKER_STATE if state == :closed
            return { state: :half_open, cooldown_until: nil }.freeze if state == :open && cooldown_until && cooldown_until <= now

            { state:, cooldown_until: }.freeze
          end

          def half_open_probe_tokens(rows, scope_key)
            payload = PolicyStateRow.new(row: half_open_probe_row(rows, scope_key)).payload
            Array(payload['reservation_tokens'] || payload[:reservation_tokens]).freeze
          end

          def active_probe_tokens(rows)
            rows.fetch(:reservations).map { |row| row.fetch(:reservation_token) }
          end

          def circuit_breaker_scope_blocked?(rows, scope_key, now, policy)
            state = breaker_state(rows, scope_key, now, policy).fetch(:state)
            return true if state == :open
            return false unless state == :half_open

            half_open_probe_tokens(rows, scope_key).count { |token| active_probe_tokens(rows).include?(token) } >= policy.half_open_limit
          end

          def breaker_policy_rows(context, rows, job, now, failure_classification: nil, reservation_token: nil, success: false)
            scope_keys = ScopeKeySet.new(job:, explicit_scope: nil).to_a
            existing_policy_rows = rows.fetch(:policy_state, [])
            policy_changes = { inserts: [], updates: [], deletes: [] }

            scope_keys.each do |scope_key|
              apply_breaker_policy_rows(
                context:, rows:, existing_policy_rows:, policy_changes:,
                scope_key:, now:, failure_classification:, reservation_token:, success:
              )
            end

            policy_changes
          end

          def apply_breaker_policy_rows(
            context:, rows:, existing_policy_rows:, policy_changes:,
            scope_key:, now:, failure_classification:, reservation_token:, success:
          )
            policy = store.send(:circuit_breaker_policy_set).policies[scope_key]
            return unless policy

            state_row = breaker_state_row(rows, scope_key)
            failures_row = breaker_failures_row(rows, scope_key)
            probes_row = half_open_probe_row(rows, scope_key)
            transition = breaker_policy_transition(
              rows, scope_key, now, policy, failure_classification:, reservation_token:, success:
            )

            write_breaker_policy_row(
              context, existing_policy_rows, policy_changes,
              scope_key:, existing_row: state_row, policy_kind: 'breaker_state', payload: transition.fetch(:state), updated_at: now
            )
            write_breaker_policy_row(
              context, existing_policy_rows, policy_changes,
              scope_key:, existing_row: failures_row, policy_kind: 'breaker_failures',
              payload: { timestamps: transition.fetch(:failures) }, updated_at: now
            )
            write_breaker_policy_row(
              context, existing_policy_rows, policy_changes,
              scope_key:, existing_row: probes_row, policy_kind: 'half_open_probes',
              payload: { reservation_tokens: transition.fetch(:probe_tokens) }, updated_at: now
            )
          end

          def breaker_policy_transition(rows, scope_key, now, policy, failure_classification:, reservation_token:, success:)
            current_state = breaker_state(rows, scope_key, now, policy)
            current_failures = breaker_failures(rows, scope_key, now, policy)
            current_probe_tokens = filtered_probe_tokens(rows, scope_key)
            next_probe_tokens = reservation_token_for_half_open(current_probe_tokens, current_state, reservation_token)
            next_state = current_state
            next_failures = current_failures

            if success && current_state.fetch(:state) == :half_open
              next_state = CLOSED_BREAKER_STATE
              next_failures = []
              next_probe_tokens = []
            elsif counted_breaker_failure?(failure_classification)
              next_state, next_failures, next_probe_tokens = next_failure_transition(
                current_state, current_failures, next_probe_tokens, now, policy
              )
            end

            { state: next_state, failures: next_failures, probe_tokens: next_probe_tokens }
          end

          def filtered_probe_tokens(rows, scope_key)
            tokens = active_probe_tokens(rows)
            half_open_probe_tokens(rows, scope_key).select { |token| tokens.include?(token) }
          end

          def reservation_token_for_half_open(current_probe_tokens, current_state, reservation_token)
            return current_probe_tokens unless reservation_token && current_state.fetch(:state) == :half_open

            (current_probe_tokens + [reservation_token]).uniq
          end

          def counted_breaker_failure?(failure_classification)
            failure_classification && COUNTED_FAILURE_CLASSIFICATIONS.include?(failure_classification)
          end

          def next_failure_transition(current_state, current_failures, current_probe_tokens, now, policy)
            if current_state.fetch(:state) == :half_open
              [{ state: :open, cooldown_until: now + policy.cooldown }.freeze, [now], []]
            else
              next_failures = current_failures + [now]
              next_state = next_failures.length >= policy.failure_threshold ? { state: :open, cooldown_until: now + policy.cooldown }.freeze : current_state
              next_probe_tokens = next_state.fetch(:state) == :open ? [] : current_probe_tokens
              [next_state, next_failures, next_probe_tokens]
            end
          end

          def write_breaker_policy_row(
            context, existing_policy_rows, policy_changes,
            scope_key:, existing_row:, policy_kind:, payload:, updated_at:
          )
            add_policy_state_change(
              context, existing_policy_rows, policy_changes.fetch(:inserts), policy_changes.fetch(:updates), policy_changes.fetch(:deletes),
              policy_kind:, scope_key:, existing_row:, payload:, updated_at:
            )
          end

          def stuck_job_policy_rows(context, rows, job, now, clear: false)
            existing_row = stuck_job_recovery_row(rows, job.id)
            payload =
              if clear
                {}
              else
                existing_payload = PolicyStateRow.new(row: existing_row).payload
                {
                  recovery_count: (existing_payload['recovery_count'] || existing_payload[:recovery_count] || 0) + 1,
                  last_recovered_at: now,
                  last_recovery_reason: STUCK_JOB_RECOVERY_REASON
                }
              end
            policy_inserts = []
            policy_updates = []
            policy_deletes = []
            add_policy_state_change(
              context, rows.fetch(:policy_state, []), policy_inserts, policy_updates, policy_deletes,
              policy_kind: 'stuck_job_recovery',
              scope_key: "job:#{job.id}",
              existing_row:,
              payload:,
              updated_at: now
            )
            { inserts: policy_inserts, updates: policy_updates, deletes: policy_deletes }
          end

          def add_policy_state_change(context, existing_rows, inserts, updates, deletes, policy_kind:, scope_key:, existing_row:, payload:, updated_at:)
            normalized_payload = PolicyStateRecord.stringify_payload(payload)
            if delete_policy_payload?(policy_kind, normalized_payload)
              deletes << existing_row if existing_row
              return
            end

            scope_kind, scope_value = PolicyStateRecord.scope_components(scope_key)
            row = PolicyStateRecord.new(
              namespace: context.namespace,
              policy_kind:,
              scope: { kind: scope_kind, value: scope_value },
              state_payload: normalized_payload,
              updated_at:
            ).to_h
            if existing_row || existing_rows.any? { |candidate| candidate.fetch(:policy_kind) == policy_kind && policy_scope_key(candidate) == scope_key }
              updates << row
            else
              inserts << row
            end
          end

          def delete_policy_payload?(policy_kind, payload)
            case policy_kind
            when 'breaker_state'
              payload['state'] == 'closed'
            when 'breaker_failures'
              Array(payload['timestamps']).empty?
            when 'half_open_probes'
              Array(payload['reservation_tokens']).empty?
            when 'stuck_job_recovery'
              payload.empty?
            else
              false
            end
          end
        end

        # Shared dead-letter recovery helpers used by replay and retry operations.
        module DeadLetterRecoverySupport
          private

          def recover_dead_letters(context, action, next_state:, next_retry_at: nil)
            now = normalize_time(:now, request.fetch(:now), error_class: InvalidQueueStoreOperationError)
            normalized_job_ids = normalize_job_ids(request.fetch(:job_ids))
            bulk_mutation_result(context, action:, job_ids: normalized_job_ids, now:) do |job, rows, skipped_jobs, job_id|
              recovered_job = recover_dead_letter_job(job, next_state, next_retry_at, now)
              unless recovered_job
                skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :ineligible_state, state: job.state).to_h
                next
              end

              if uniqueness_conflict?(recovered_job, rows, now:, exclude_job_id: job_id)
                skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :uniqueness_conflict, state: job.state).to_h
                next
              end

              recovered_job
            end
          end

          def recover_dead_letter_job(job, next_state, next_retry_at, now)
            return nil unless job.state == :dead_letter && job.can_transition_to?(next_state)

            job.transition_to(
              next_state,
              updated_at: now,
              next_retry_at:,
              failure_classification: nil,
              dead_letter_reason: nil,
              dead_lettered_at: nil,
              dead_letter_source_state: nil
            )
          end
        end

        # Shared backpressure gating and rate-limit policy mutation helpers.
        module BackpressurePolicySupport
          private

          def concurrency_blocked?(rows, job)
            ScopeKeySet.new(job:, explicit_scope: job.concurrency_scope).to_a.any? do |scope_key|
              policy = store.send(:policy_set).concurrency[scope_key]
              next false unless policy

              ActiveConcurrencyCounter.new(rows:, scope_key:).count >= policy.limit
            end
          end

          def rate_limit_blocked?(rows, job, now)
            ScopeKeySet.new(job:, explicit_scope: job.rate_limit_scope).to_a.any? do |scope_key|
              policy = store.send(:policy_set).rate_limits[scope_key]
              next false unless policy

              rate_limit_admissions(rows, scope_key, now, policy).length >= policy.limit
            end
          end

          def rate_limit_policy_rows(context, rows, job, now)
            policy_inserts = []
            policy_updates = []
            policy_deletes = []

            ScopeKeySet.new(job:, explicit_scope: job.rate_limit_scope).to_a.each do |scope_key|
              policy = store.send(:policy_set).rate_limits[scope_key]
              next unless policy

              existing_row = row_for_policy_kind(rows, 'rate_limit_admissions', scope_key)
              timestamps = rate_limit_admissions(rows, scope_key, now, policy) + [now]
              add_policy_state_change(
                context, rows.fetch(:policy_state, []), policy_inserts, policy_updates, policy_deletes,
                policy_kind: 'rate_limit_admissions',
                scope_key:,
                existing_row:,
                payload: { timestamps: timestamps },
                updated_at: now
              )
            end

            { inserts: policy_inserts, updates: policy_updates, deletes: policy_deletes }
          end

          def rate_limit_admissions(rows, scope_key, now, policy)
            payload = PolicyStateRow.new(row: row_for_policy_kind(rows, 'rate_limit_admissions', scope_key)).payload
            Array(payload['timestamps'] || payload[:timestamps]).select { |timestamp| timestamp > now - policy.period }
          end
        end

        # Shared reservation lookup and lease-expiration validation helpers.
        module LeaseSupport
          private

          def lease_context(context)
            rows = context.rows
            reservation_token = request.fetch(:reservation_token)
            reservation_row = find_reservation_row(rows.fetch(:reservations), reservation_token)
            now = normalize_time(:now, request.fetch(:now), error_class: InvalidQueueStoreOperationError)
            raise UnknownReservationError, "reservation #{reservation_token.inspect} was not found" unless reservation_row

            raise_expired_reservation_error!(reservation_token, reservation_row, now)

            job_row = rows.fetch(:jobs).find { |row| row.fetch(:job_id) == reservation_row.fetch(:job_id) }
            LeaseContext.new(
              job: JobRow.new(row: job_row).to_job,
              now:,
              reservation_row:,
              reservation_token:
            )
          end

          def raise_expired_reservation_error!(reservation_token, reservation_row, now)
            return unless reservation_row.fetch(:lease_expires_at) <= now

            raise ExpiredReservationError, "reservation #{reservation_token.inspect} has expired"
          end
        end

        # Reserves the next durable candidate that passes queue and policy gates.
        class Reserve < Operation
          include RequestSupport
          include SharedSupport

          def call(context:)
            reserve_request = normalized_reserve_request
            reservation_token_sequence = context.metadata.fetch(:reservation_token_sequence, 0)
            candidate = CandidateSelector.new(operation: self, rows: context.rows, reserve_request:).call
            return OperationResult.new(value: nil, mutation_plan: MutationPlan.new, persist: false) unless candidate

            outcome = ReservationBuilder.new(
              operation: self,
              context:,
              reserve_request:,
              candidate:,
              reservation_token_sequence:
            ).call

            OperationResult.new(
              value: outcome.reservation,
              mutation_plan: MutationPlanBuilder.new(
                operation: self,
                context:,
                outcome:
              ).call,
              persist: true
            )
          end

          private

          def normalized_reserve_request
            normalize_reserve_request(
              worker_id: request.fetch(:worker_id),
              lease_duration: request.fetch(:lease_duration),
              now: request.fetch(:now),
              queue: request[:queue],
              queues: request[:queues],
              handler_names: request[:handler_names]
            )
          end
        end

        # Releases an active reservation back into the durable queued state.
        class Release < Operation
          include SharedSupport
          include RowSupport
          include LeaseSupport

          def call(context:)
            ReleaseResultBuilder.new(operation: self, context:, lease: lease_context(context)).build
          end
        end

        # Promotes a reserved job into the running execution phase.
        class StartExecution < Operation
          include SharedSupport
          include RowSupport
          include LeaseSupport

          def call(context:)
            StartExecutionResultBuilder.new(operation: self, context:, lease: lease_context(context)).build
          end
        end

        # Completes a running job and clears its active execution lease.
        class CompleteExecution < Operation
          include SharedSupport
          include RowSupport
          include LeaseSupport
          include ReliabilityPolicySupport

          def call(context:)
            lease = lease_context(context)
            rows = context.rows
            running_job = lease.job
            now = lease.now
            succeeded_job = completed_execution_job(running_job, now)
            breaker_rows = breaker_policy_rows(context, rows, running_job, now, success: true)
            stuck_rows = stuck_job_policy_rows(context, rows, running_job, now, clear: true)
            workflow_effects = WorkflowJobEffects.new(operation: self, context:, job: succeeded_job)

            OperationResult.new(
              value: succeeded_job,
              mutation_plan: completed_execution_plan(
                context, lease, succeeded_job, workflow_effects, breaker_rows, stuck_rows
              ),
              persist: true
            )
          end

          private

          def completed_execution_job(running_job, now)
            running_job.transition_to(:succeeded, updated_at: now, next_retry_at: nil, failure_classification: nil)
          end

          def completed_execution_plan(context, lease, succeeded_job, workflow_effects, breaker_rows, stuck_rows)
            MutationPlan.new(
              updates: completed_execution_updates(context, succeeded_job, workflow_effects, breaker_rows, stuck_rows),
              inserts: completed_execution_inserts(breaker_rows, stuck_rows, workflow_effects),
              deletes: completed_execution_deletes(lease, breaker_rows, stuck_rows)
            )
          end

          def completed_execution_updates(context, succeeded_job, workflow_effects, breaker_rows, stuck_rows)
            workflow_updates = workflow_effects.workflow_updates
            {
              jobs: [JobRecord.new(namespace: context.namespace, job: succeeded_job).to_h],
              workflow_steps: workflow_updates.fetch(:workflow_steps),
              workflow_batches: workflow_updates.fetch(:workflow_batches),
              policy_state: breaker_rows.fetch(:updates) + stuck_rows.fetch(:updates)
            }
          end

          def completed_execution_inserts(breaker_rows, stuck_rows, workflow_effects)
            {
              policy_state: breaker_rows.fetch(:inserts) + stuck_rows.fetch(:inserts),
              workflow_history: workflow_effects.workflow_history_rows
            }
          end

          def completed_execution_deletes(lease, breaker_rows, stuck_rows)
            {
              reservations: [lease.reservation_row],
              policy_state: breaker_rows.fetch(:deletes) + stuck_rows.fetch(:deletes)
            }
          end
        end

        # Applies retry or dead-letter transitions for a failed running job.
        class FailExecution < Operation
          include SharedSupport
          include RowSupport
          include LeaseSupport
          include ReliabilityPolicySupport

          def call(context:)
            lease = lease_context(context)
            failure_classification = normalized_failure_classification
            retry_policy = normalized_retry_policy
            finalized_job = finalize_failed_job(lease.job, lease.now, retry_policy, failure_classification)
            breaker_rows = breaker_policy_rows(
              context,
              context.rows,
              lease.job,
              lease.now,
              failure_classification:
            )

            OperationResult.new(
              value: finalized_job,
              mutation_plan: failed_job_mutation_plan(context, lease, finalized_job, breaker_rows),
              persist: true
            )
          end

          private

          def normalized_failure_classification
            Karya::Internal::FailureClassification.normalize(
              request.fetch(:failure_classification),
              error_class: InvalidQueueStoreOperationError
            )
          end

          def normalized_retry_policy
            Karya::Internal::RetryPolicyNormalizer.new(
              request[:retry_policy],
              error_class: InvalidQueueStoreOperationError
            ).normalize
          end

          def finalize_failed_job(running_job, now, retry_policy, failure_classification)
            return failed_job(running_job, now, failure_classification, retry_policy) unless retry_policy

            decision = retry_policy.decision_for(
              attempt: running_job.attempt,
              failure_classification:,
              jitter_key: running_job.id
            )
            return retry_pending_job(running_job, now, retry_policy, failure_classification, decision.delay) if decision.action == :retry
            return dead_letter_job(running_job, now, retry_policy, failure_classification, decision.reason) if decision.action == :escalate

            failed_job(running_job, now, failure_classification, retry_policy)
          end

          def failed_job(running_job, now, failure_classification, retry_policy)
            running_job.transition_to(
              :failed,
              updated_at: now,
              next_retry_at: nil,
              failure_classification:,
              retry_policy:
            )
          end

          def retry_pending_job(running_job, now, retry_policy, failure_classification, delay)
            failed = failed_job(running_job, now, failure_classification, retry_policy)
            failed.transition_to(
              :retry_pending,
              updated_at: now,
              next_retry_at: now + delay,
              failure_classification:,
              retry_policy:
            )
          end

          def dead_letter_job(running_job, now, retry_policy, failure_classification, reason)
            failed = failed_job(running_job, now, failure_classification, retry_policy)
            failed.transition_to(
              :dead_letter,
              updated_at: now,
              next_retry_at: nil,
              failure_classification: failed.failure_classification,
              dead_letter_reason: reason == :retry_exhausted ? 'retry-policy-exhausted' : 'retry-policy-escalated',
              dead_lettered_at: now,
              dead_letter_source_state: failed.state
            )
          end

          def failed_job_mutation_plan(context, lease, finalized_job, breaker_rows)
            workflow_effects = WorkflowJobEffects.new(operation: self, context:, job: finalized_job)
            workflow_updates = workflow_effects.workflow_updates
            queue_entries =
              if finalized_job.state == :retry_pending
                [QueueEntryRecord.new(
                  namespace: context.namespace,
                  job: finalized_job,
                  insertion_sequence: QueueEntrySequence.new(
                    queue_entries: context.rows.fetch(:queue_entries),
                    queue: finalized_job.queue
                  ).next_value
                ).to_h]
              else
                []
              end
            MutationPlan.new(
              updates: {
                jobs: [JobRecord.new(namespace: context.namespace, job: finalized_job).to_h],
                workflow_steps: workflow_updates.fetch(:workflow_steps),
                workflow_batches: workflow_updates.fetch(:workflow_batches),
                policy_state: breaker_rows.fetch(:updates)
              },
              inserts: {
                queue_entries: queue_entries,
                policy_state: breaker_rows.fetch(:inserts),
                workflow_history: workflow_effects.workflow_history_rows
              },
              deletes: {
                reservations: [lease.reservation_row],
                policy_state: breaker_rows.fetch(:deletes)
              }
            )
          end
        end

        # Enqueues one submission job into the durable row model.
        class Enqueue < Operation
          include RowSupport

          def call(context:)
            job = request.fetch(:job)
            raise InvalidEnqueueError, 'job must be a Karya::Job' unless job.is_a?(Job)
            raise InvalidEnqueueError, 'job must be in :submission state before enqueue' unless job.state == :submission

            now = request.fetch(:now)
            raise InvalidEnqueueError, 'now must be a Time' unless now.is_a?(Time)

            uniqueness_evaluator = UniquenessEvaluator.new(rows: context.rows, now:)
            uniqueness_evaluator.raise_duplicate_enqueue_error(uniqueness_evaluator.decision_for(job:))

            queued_job = job.transition_to(:queued, updated_at: now)
            OperationResult.new(
              value: queued_job,
              mutation_plan: MutationPlan.new(
                inserts: JobRuntimeRows.new(namespace: context.namespace, rows: context.rows).enqueue_insert_groups_for(queued_job)
              ),
              persist: true
            )
          end
        end

        # Enqueues multiple submission jobs and optional batch membership rows.
        class EnqueueMany < Operation
          include SharedSupport
          include RowSupport
          include BulkMutationSupport

          # Checks new enqueue-many jobs against the jobs already accepted in the same request.
          class DuplicateBatchGuard
            def initialize(job:, accepted_jobs:, now:)
              @job = job
              @accepted_jobs = accepted_jobs
              @now = now
              @queued_job = build_queued_job
            end

            def validate
              accepted_jobs.each do |accepted_job|
                raise DuplicateJobError, "job #{inspected_job_id} is already present in the queue store" if accepted_job.id == job_id
                if idempotency_key && accepted_job.idempotency_key == idempotency_key
                  raise DuplicateIdempotencyKeyError,
                        "job #{inspected_job_id} conflicts with idempotency_key #{DuplicateKeySummary.new(idempotency_key)}"
                end
                next unless uniqueness_key && accepted_job.uniqueness_key == uniqueness_key

                next unless uniqueness_conflict_with?(accepted_job)

                raise DuplicateUniquenessKeyError,
                      "job #{inspected_job_id} conflicts with uniqueness_key #{DuplicateKeySummary.new(uniqueness_key)}"
              end
            end

            private

            attr_reader :accepted_jobs, :job, :now, :queued_job

            def job_id = job.id

            def inspected_job_id = job_id.inspect

            def idempotency_key = job.idempotency_key

            def uniqueness_key = job.uniqueness_key

            def build_queued_job
              return nil unless uniqueness_key
              return job if job.state == :queued

              job.transition_to(:queued, updated_at: now)
            end

            def uniqueness_conflict_with?(accepted_job)
              evaluator = UniquenessEvaluator.new(
                rows: { jobs: [JobRecord.new(namespace: 'batch', job: accepted_job).to_h], reservations: [] },
                now:
              )
              !!evaluator.send(:duplicate_uniqueness_job, queued_job, exclude_job_id: nil)
            end
          end

          # Builds optional workflow batch metadata for enqueue-many requests.
          class OptionalBatchBuilder
            def initialize(request:, jobs:, now:, max_batch_size:, existing_batches:)
              @request = request
              @jobs = jobs
              @now = now
              @max_batch_size = max_batch_size
              @existing_batches = existing_batches
            end

            def build
              batch_id = request[:batch_id]
              return nil unless batch_id

              batch = Workflow::Batch.new(
                id: batch_id,
                job_ids: jobs.map(&:id),
                created_at: now,
                updated_at: now,
                max_size: max_batch_size
              )
              batch_id_value = batch.id
              if existing_batches.any? { |row| row.fetch(:batch_id) == batch_id_value }
                raise Workflow::DuplicateBatchError, "batch #{batch_id_value.inspect} already exists"
              end

              batch
            end

            private

            attr_reader :existing_batches, :jobs, :max_batch_size, :now, :request
          end

          # Transitions validated submission jobs into queued state for enqueue-many.
          class QueuedJobsBuilder
            include RowSupport

            def initialize(namespace:, rows:, jobs:, now:)
              @namespace = namespace
              @rows = rows
              @jobs = jobs
              @now = now
            end

            def build
              accepted_jobs = []
              mutated_rows = rows.merge(namespace:)

              jobs.map do |job|
                validate_job(job, accepted_jobs, mutated_rows)
                queued_job = job.transition_to(:queued, updated_at: now)
                accepted_jobs << queued_job
                mutated_rows = append_job_rows(mutated_rows, queued_job)
                queued_job
              end
            end

            private

            attr_reader :jobs, :namespace, :now, :rows

            def validate_job(job, accepted_jobs, mutated_rows)
              raise InvalidEnqueueError, 'jobs entries must be Karya::Job' unless job.is_a?(Job)
              raise InvalidEnqueueError, 'job must be in :submission state before enqueue' unless job.state == :submission

              uniqueness_evaluator = UniquenessEvaluator.new(rows: mutated_rows, now:)
              uniqueness_evaluator.raise_duplicate_enqueue_error(uniqueness_evaluator.decision_for(job:))
              DuplicateBatchGuard.new(job:, accepted_jobs:, now:).validate
            end

            def append_job_rows(current_rows, queued_job)
              JobRuntimeRows.new(namespace:, rows: current_rows).append_enqueued(queued_job)
            end
          end

          # Builds the durable insert groups for enqueue-many mutations.
          class InsertBuilder
            include RowSupport

            def initialize(namespace:, existing_rows:, queued_jobs:, batch:)
              @namespace = namespace
              @existing_rows = existing_rows
              @queued_jobs = queued_jobs
              @batch = batch
            end

            def build
              queue_entries = existing_rows.fetch(:queue_entries).dup
              inserts = { jobs: [], queue_entries: [], idempotency_keys: [], uniqueness_keys: [] }
              queued_jobs.each do |job|
                append_job_rows(inserts, queue_entries, job)
              end
              append_batch_rows(inserts) if batch
              inserts.transform_values(&:freeze)
            end

            private

            attr_reader :batch, :existing_rows, :namespace, :queued_jobs

            def append_job_rows(inserts, queue_entries, job)
              inserts[:jobs] << JobRecord.new(namespace:, job:).to_h
              queue_entry_row = QueueEntryRecord.new(
                namespace:,
                job:,
                insertion_sequence: QueueEntrySequence.new(queue_entries:, queue: job.queue).next_value
              ).to_h
              inserts[:queue_entries] << queue_entry_row
              queue_entries << queue_entry_row
              inserts[:idempotency_keys] << IdempotencyKeyRecord.new(namespace:, job:).to_h if job.idempotency_key
              inserts[:uniqueness_keys] << UniquenessKeyRecord.new(namespace:, job:).to_h if job.uniqueness_key && job.uniqueness_scope
            end

            def append_batch_rows(inserts)
              jobs_index = queued_jobs.to_h { |job| [job.id, job] }
              registration = Struct.new(:workflow_id, :workflow_family, :workflow_version).new(
                BATCH_PLACEHOLDER_WORKFLOW_ID,
                BATCH_PLACEHOLDER_WORKFLOW_ID,
                BATCH_PLACEHOLDER_WORKFLOW_ID
              )
              inserts[:workflow_batches] = [
                WorkflowBatchRecord.new(namespace:, batch:, registration:, jobs_by_id: jobs_index).to_h
              ]
              inserts[:workflow_steps] = batch.job_ids.each_with_index.map do |job_id, index|
                job = jobs_index.fetch(job_id)
                {
                  namespace:,
                  batch_id: batch.id,
                  step_id: job_id,
                  step_sequence: index + 1,
                  job_id:,
                  state: job.state.to_s,
                  dependency_payload: PayloadCodec.dump([]),
                  metadata_payload: PayloadCodec.dump({}),
                  updated_at: job.updated_at
                }
              end
            end
          end

          def call(context:)
            now, jobs = normalized_enqueue_many_request
            namespace = context.namespace
            rows = context.rows
            batch = OptionalBatchBuilder.new(
              request:,
              jobs:,
              now:,
              max_batch_size: store.send(:max_batch_size),
              existing_batches: rows.fetch(:workflow_batches, [])
            ).build
            queued_jobs = QueuedJobsBuilder.new(
              namespace:,
              rows:,
              jobs:,
              now:
            ).build

            OperationResult.new(
              value: Karya::QueueStore::Internal::BulkMutationReport.new(
                action: :enqueue_many,
                performed_at: now,
                requested_job_ids: jobs.map(&:id),
                changed_jobs: queued_jobs,
                skipped_jobs: []
              ),
              mutation_plan: MutationPlan.new(
                inserts: InsertBuilder.new(
                  namespace:,
                  existing_rows: rows,
                  queued_jobs:,
                  batch:
                ).build
              ),
              persist: !queued_jobs.empty?
            )
          end

          private

          def normalized_enqueue_many_request
            now = request.fetch(:now)
            raise InvalidEnqueueError, 'now must be a Time' unless now.is_a?(Time)

            jobs = request.fetch(:jobs)
            raise InvalidEnqueueError, 'jobs must be an Array' unless jobs.is_a?(Array)

            [now, jobs]
          end
        end

        # Evaluates enqueue-time uniqueness and idempotency conflicts without mutating state.
        class UniquenessDecision < Operation
          def call(context:)
            job = request.fetch(:job)
            raise InvalidEnqueueError, 'job must be a Karya::Job' unless job.is_a?(Job)
            raise InvalidEnqueueError, 'job must be in :submission state before enqueue' unless job.state == :submission

            now = request.fetch(:now)
            raise InvalidEnqueueError, 'now must be a Time' unless now.is_a?(Time)

            OperationResult.new(
              value: UniquenessEvaluator.new(rows: context.rows, now:).decision_for(job:),
              mutation_plan: MutationPlan.new,
              persist: false
            )
          end
        end

        # Captures the durable uniqueness and idempotency blocking snapshot.
        class UniquenessSnapshot < Operation
          def call(context:)
            now = request.fetch(:now)
            raise InvalidQueueStoreOperationError, 'now must be a Time' unless now.is_a?(Time)

            OperationResult.new(
              value: UniquenessEvaluator.new(rows: context.rows, now:).snapshot,
              mutation_plan: MutationPlan.new,
              persist: false
            )
          end
        end

        # Marks one queue as paused in durable policy state.
        class PauseQueue < Operation
          def call(context:)
            queue = normalize_identifier(:queue, request.fetch(:queue), error_class: InvalidQueueStoreOperationError)
            now = normalize_time(:now, request.fetch(:now), error_class: InvalidQueueStoreOperationError)
            existing_row = context.rows.fetch(:policy_state).first
            changed = existing_row.nil?
            plan = changed ? MutationPlan.new(inserts: { policy_state: [paused_queue_row(context.namespace, queue, now)] }) : MutationPlan.new

            OperationResult.new(
              value: Karya::QueueStore::Internal::QueueControlResult.new(
                action: :pause_queue,
                performed_at: now,
                queue:,
                paused: true,
                changed:
              ),
              mutation_plan: plan,
              persist: changed
            )
          end

          private

          include SharedSupport

          def paused_queue_row(namespace, queue, now)
            PolicyStateRecord.new(
              namespace:,
              policy_kind: 'paused_queue',
              scope: { kind: 'queue', value: queue },
              state_payload: { paused: true },
              updated_at: now
            ).to_h
          end
        end

        # Clears durable paused state for one queue.
        class ResumeQueue < Operation
          include SharedSupport

          def call(context:)
            queue = normalize_identifier(:queue, request.fetch(:queue), error_class: InvalidQueueStoreOperationError)
            now = normalize_time(:now, request.fetch(:now), error_class: InvalidQueueStoreOperationError)
            existing_row = context.rows.fetch(:policy_state).first
            changed = !existing_row.nil?
            plan = changed ? MutationPlan.new(deletes: { policy_state: [existing_row] }) : MutationPlan.new

            OperationResult.new(
              value: Karya::QueueStore::Internal::QueueControlResult.new(
                action: :resume_queue,
                performed_at: now,
                queue:,
                paused: false,
                changed:
              ),
              mutation_plan: plan,
              persist: changed
            )
          end
        end

        # Retries eligible failed or retry-pending jobs in bulk.
        class RetryJobs < Operation
          include SharedSupport
          include RowSupport
          include BulkMutationSupport

          def call(context:)
            now = normalize_time(:now, request.fetch(:now), error_class: InvalidQueueStoreOperationError)
            normalized_job_ids = normalize_job_ids(request.fetch(:job_ids))
            bulk_mutation_result(context, action: :retry_jobs, job_ids: normalized_job_ids, now:) do |job, rows, skipped_jobs, job_id|
              retried_job = retried_job_for(job, now)
              unless retried_job
                skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :ineligible_state, state: job.state).to_h
                next
              end

              if uniqueness_conflict?(retried_job, rows, now:, exclude_job_id: job_id)
                skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :uniqueness_conflict, state: job.state).to_h
                next
              end

              retried_job
            end
          end

          private

          def retried_job_for(job, now)
            case job.state
            when :failed
              job.transition_to(:retry_pending, updated_at: now, next_retry_at: now).transition_to(
                :queued,
                updated_at: now,
                next_retry_at: nil,
                failure_classification: nil
              )
            when :retry_pending
              job.transition_to(:queued, updated_at: now, next_retry_at: nil, failure_classification: nil)
            end
          end
        end

        # Cancels eligible jobs in bulk.
        class CancelJobs < Operation
          include SharedSupport
          include RowSupport
          include BulkMutationSupport

          def call(context:)
            now = normalize_time(:now, request.fetch(:now), error_class: InvalidQueueStoreOperationError)
            normalized_job_ids = normalize_job_ids(request.fetch(:job_ids))
            bulk_mutation_result(context, action: :cancel_jobs, job_ids: normalized_job_ids, now:) do |job, _rows, skipped_jobs, job_id|
              unless job.can_transition_to?(:cancelled)
                skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :ineligible_state, state: job.state).to_h
                next
              end

              job.transition_to(:cancelled, updated_at: now, next_retry_at: nil, failure_classification: nil)
            end
          end
        end

        # Moves eligible jobs into dead-letter state in bulk.
        class DeadLetterJobs < Operation
          include SharedSupport
          include RowSupport
          include BulkMutationSupport

          def call(context:)
            now = normalize_time(:now, request.fetch(:now), error_class: InvalidQueueStoreOperationError)
            normalized_job_ids = normalize_job_ids(request.fetch(:job_ids))
            normalized_reason = Karya::Internal::DeadLetterReason.normalize(
              request.fetch(:reason),
              error_class: InvalidQueueStoreOperationError
            )
            bulk_mutation_result(context, action: :dead_letter_jobs, job_ids: normalized_job_ids, now:) do |job, _rows, skipped_jobs, job_id|
              unless job.can_transition_to?(:dead_letter)
                skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :ineligible_state, state: job.state).to_h
                next
              end

              job.transition_to(
                :dead_letter,
                updated_at: now,
                next_retry_at: nil,
                failure_classification: job.failure_classification,
                dead_letter_reason: normalized_reason,
                dead_lettered_at: now,
                dead_letter_source_state: job.state
              )
            end
          end
        end

        # Replays eligible dead-letter jobs back to the queue.
        class ReplayDeadLetterJobs < Operation
          include SharedSupport
          include RowSupport
          include BulkMutationSupport
          include DeadLetterRecoverySupport

          def call(context:)
            recover_dead_letters(context, :replay_dead_letter_jobs, next_state: :queued)
          end
        end

        # Requeues eligible dead-letter jobs into retry-pending state.
        class RetryDeadLetterJobs < Operation
          include SharedSupport
          include RowSupport
          include BulkMutationSupport
          include DeadLetterRecoverySupport

          def call(context:)
            next_retry_at = normalize_time(:next_retry_at, request.fetch(:next_retry_at), error_class: InvalidQueueStoreOperationError)
            recover_dead_letters(context, :retry_dead_letter_jobs, next_state: :retry_pending, next_retry_at:)
          end
        end

        # Discards eligible dead-letter jobs into cancelled state.
        class DiscardDeadLetterJobs < Operation
          include SharedSupport
          include RowSupport
          include BulkMutationSupport

          def call(context:)
            now = normalize_time(:now, request.fetch(:now), error_class: InvalidQueueStoreOperationError)
            normalized_job_ids = normalize_job_ids(request.fetch(:job_ids))
            bulk_mutation_result(context, action: :discard_dead_letter_jobs, job_ids: normalized_job_ids, now:) do |job, _rows, skipped_jobs, job_id|
              unless job.state == :dead_letter && job.can_transition_to?(:cancelled)
                skipped_jobs << Karya::Internal::BulkMutation::SkippedJob.new(job_id:, reason: :ineligible_state, state: job.state).to_h
                next
              end

              job.transition_to(
                :cancelled,
                updated_at: now,
                next_retry_at: nil,
                failure_classification: nil,
                dead_letter_reason: nil,
                dead_lettered_at: nil,
                dead_letter_source_state: nil
              )
            end
          end
        end

        # Recovers expired work for one worker while keeping global maintenance scoped.
        class RecoverOrphanedJobs < Operation
          include SharedSupport
          include RowSupport
          include BulkMutationSupport
          include RecoverySupport
          include ReliabilityPolicySupport

          def call(context:)
            worker_id = normalize_identifier(:worker_id, request.fetch(:worker_id), error_class: InvalidQueueStoreOperationError)
            now = expiration_time(request)
            recovery = recovery_pass(context, now, worker_id:)

            OperationResult.new(
              value: recovery.fetch(:recovered_jobs),
              mutation_plan: recovery.fetch(:plan),
              persist: recovery.fetch(:changed)
            )
          end
        end

        # Recovers all expired reservations and executions plus related maintenance.
        class RecoverInFlight < Operation
          include SharedSupport
          include RowSupport
          include BulkMutationSupport
          include RecoverySupport
          include ReliabilityPolicySupport

          def call(context:)
            now = expiration_time(request)
            recovery = recovery_pass(context, now)

            OperationResult.new(
              value: Karya::QueueStore::Internal::RecoveryReport.new(
                recovered_at: now,
                expired_jobs: recovery.fetch(:expired_jobs),
                recovered_reserved_jobs: recovery.fetch(:recovered_reserved_jobs),
                recovered_running_jobs: recovery.fetch(:recovered_running_jobs),
                changed: recovery.fetch(:changed)
              ),
              mutation_plan: recovery.fetch(:plan),
              persist: recovery.fetch(:changed)
            )
          end
        end

        # Returns the set of jobs expired or recovered during a lease-expiration pass.
        class ExpireReservations < Operation
          include SharedSupport
          include RowSupport
          include BulkMutationSupport
          include RecoverySupport
          include ReliabilityPolicySupport

          def call(context:)
            now = expiration_time(request)
            recovery = recovery_pass(context, now)
            expired_jobs = recovery.fetch(:expired_jobs) + recovery.fetch(:recovered_reserved_jobs) + recovery.fetch(:recovered_running_jobs)

            OperationResult.new(
              value: expired_jobs,
              mutation_plan: recovery.fetch(:plan),
              persist: recovery.fetch(:changed)
            )
          end
        end

        # Expires queued or retry-pending jobs whose job-level expiry has passed.
        class ExpireJobs < Operation
          include SharedSupport
          include RowSupport
          include BulkMutationSupport
          include RecoverySupport

          def call(context:)
            now = expiration_time(request)
            namespace = context.namespace
            rows = context.rows.merge(namespace:)
            expired_jobs = []
            plans = []
            rows.fetch(:jobs).each do |job_row|
              job = JobRow.new(row: job_row).to_job
              next unless job_expired?(job, now)
              next unless RowSupport::QUEUED_STATES.include?(job.state)

              expired_job = expire_job(job, now)
              expired_jobs << expired_job
              plans << storeable_plan_for_job(context, rows, expired_job)
              rows = JobRuntimeRows.new(namespace:, rows:).replace(job_id: job.id, replacement_job: expired_job)
            end

            OperationResult.new(value: expired_jobs, mutation_plan: combine_plans(plans), persist: !expired_jobs.empty?)
          end
        end

        # Shared recovery-pass orchestration for lease and expiry maintenance.
        module RecoverySupport
          private

          def recovery_pass(context, now, worker_id: nil)
            rows = context.rows.merge(namespace: context.namespace)
            rows, expired_jobs, plans = expire_recovery_jobs(context, rows, now)
            recovered_reserved_jobs, recovered_running_jobs, plans = recover_expired_leases(context, rows, now, plans, worker_id)

            {
              expired_jobs:,
              recovered_reserved_jobs:,
              recovered_running_jobs:,
              recovered_jobs: recovered_reserved_jobs + recovered_running_jobs,
              plan: combine_plans(plans),
              changed: expired_jobs.any? || recovered_reserved_jobs.any? || recovered_running_jobs.any?
            }
          end

          def expire_recovery_jobs(context, rows, now)
            expired_jobs = []
            plans = []
            rows.fetch(:jobs).each do |job_row|
              job = JobRow.new(row: job_row).to_job
              next unless job_expired?(job, now) && RowSupport::QUEUED_STATES.include?(job.state)

              expired_job = expire_job(job, now)
              expired_jobs << expired_job
              plans << storeable_plan_for_job(context, rows, expired_job)
              rows = JobRuntimeRows.new(namespace: context.namespace, rows:).replace(job_id: job.id, replacement_job: expired_job)
            end
            [rows, expired_jobs, plans]
          end

          def recover_expired_leases(context, rows, now, plans, worker_id)
            recovered_reserved_jobs = []
            recovered_running_jobs = []
            expired_reservations(rows, now, worker_id).each do |reservation_row|
              rows, recovered_job = recover_expired_lease(context, rows, reservation_row, now, plans, recovered_reserved_jobs, recovered_running_jobs)
              rows = JobRuntimeRows.new(namespace: context.namespace, rows:).replace(job_id: recovered_job.id, replacement_job: recovered_job)
            end
            [recovered_reserved_jobs, recovered_running_jobs, plans]
          end

          def expired_reservations(rows, now, worker_id)
            rows.fetch(:reservations).sort_by { |row| row.fetch(:reserved_at) }.select do |reservation_row|
              (!worker_id || reservation_row.fetch(:worker_id) == worker_id) && reservation_row.fetch(:lease_expires_at) <= now
            end
          end

          def recover_expired_lease(context, rows, reservation_row, now, plans, recovered_reserved_jobs, recovered_running_jobs)
            job = JobRow.new(row: RowIndex.new(rows:).jobs_by_id.fetch(reservation_row.fetch(:job_id))).to_job
            if reservation_row.fetch(:phase) == 'running'
              recover_running_lease(context, rows, job, now, plans, recovered_running_jobs)
            else
              recover_reserved_lease(context, rows, job, now, plans, recovered_reserved_jobs)
            end
          end

          def recover_running_lease(context, rows, job, now, plans, recovered_running_jobs)
            recovered_job = recover_expired_execution(job, now)
            recovered_running_jobs << recovered_job
            plans << combine_plans([storeable_plan_for_job(context, rows, recovered_job),
                                    policy_plan(stuck_job_policy_rows(context, rows, job, now))])
            [rows, recovered_job]
          end

          def recover_reserved_lease(context, rows, job, now, plans, recovered_reserved_jobs)
            recovered_job = recover_expired_reservation(job, now)
            recovered_reserved_jobs << recovered_job
            plans << storeable_plan_for_job(context, rows, recovered_job)
            [rows, recovered_job]
          end

          def policy_plan(policy_rows)
            MutationPlan.new(
              inserts: { policy_state: policy_rows.fetch(:inserts) },
              updates: { policy_state: policy_rows.fetch(:updates) },
              deletes: { policy_state: policy_rows.fetch(:deletes) }
            )
          end
        end

        # Shared mutation-plan composition helpers for snapshot-style read operations.
        module BulkMutationSupport
          private

          def combine_plans(plans)
            MutationPlan.new(
              metadata_updates: plans.reduce({}) { |combined, plan| combined.merge(plan.metadata_updates) },
              inserts: combine_groups(plans, &:inserts),
              updates: combine_groups(plans, &:updates),
              deletes: combine_groups(plans, &:deletes)
            )
          end

          def combine_groups(plans)
            plans.each_with_object({}) do |plan, groups|
              yield(plan).each do |group_name, rows|
                groups[group_name] ||= []
                groups[group_name].concat(rows)
              end
            end
          end
        end

        # Rebuilds batch membership and job-state snapshots from durable rows.
        class BatchSnapshot < Operation
          include SharedSupport
          include RowSupport
          include BulkMutationSupport
          include RecoverySupport
          include ReliabilityPolicySupport

          def call(context:)
            now = normalize_time(:now, request.fetch(:now), error_class: Workflow::InvalidBatchError)
            batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, request.fetch(:batch_id))
            recovery = recovery_pass(context, now)
            namespace = context.namespace
            recovery_jobs = recovery.values_at(:expired_jobs, :recovered_reserved_jobs, :recovered_running_jobs).flatten
            rows = RecoveredRowsApplier.new(
              namespace:,
              rows: context.rows.merge(namespace:),
              jobs: recovery_jobs
            ).apply

            OperationResult.new(
              value: BatchSnapshotValueBuilder.new(rows:, batch_id:, captured_at: now).build,
              mutation_plan: recovery.fetch(:plan),
              persist: recovery.fetch(:changed)
            )
          end
        end

        # Rebuilds durable backpressure visibility across configured scopes.
        class BackpressureSnapshot < Operation
          include SharedSupport
          include RowSupport
          include BulkMutationSupport
          include BackpressurePolicySupport
          include RecoverySupport
          include ReliabilityPolicySupport

          def call(context:)
            now = normalize_time(:now, request.fetch(:now), error_class: InvalidQueueStoreOperationError)
            recovery = recovery_pass(context, now)
            namespace = context.namespace
            rows = RecoveredRowsApplier.new(
              namespace:,
              rows: context.rows.merge(namespace:),
              jobs: recovery.fetch(:expired_jobs) + recovery.fetch(:recovered_reserved_jobs) + recovery.fetch(:recovered_running_jobs)
            ).apply
            jobs = RowIndex.new(rows:).jobs_by_id.transform_values { |row| JobRow.new(row:).to_job }

            OperationResult.new(
              value: BackpressureSnapshotValueBuilder.new(store:, rows:, jobs:, now:, operation: self).build,
              mutation_plan: recovery.fetch(:plan),
              persist: recovery.fetch(:changed)
            )
          end
        end

        # Rebuilds durable circuit-breaker and recovery-state visibility.
        class ReliabilitySnapshot < Operation
          include SharedSupport
          include RowSupport
          include BulkMutationSupport
          include RecoverySupport
          include ReliabilityPolicySupport

          def call(context:)
            now = normalize_time(:now, request.fetch(:now), error_class: InvalidQueueStoreOperationError)
            recovery = recovery_pass(context, now)
            recovery_plan = recovery.fetch(:plan)
            recovery_changed = recovery.fetch(:changed)
            snapshot_rows = apply_recovery_to_rows(context.rows.merge(namespace: context.namespace), recovery)
            jobs = RowIndex.new(rows: snapshot_rows).jobs_by_id.transform_values { |row| JobRow.new(row:).to_job }

            OperationResult.new(
              value: reliability_snapshot_value(snapshot_rows, jobs, now),
              mutation_plan: recovery_plan,
              persist: recovery_changed
            )
          end

          private

          def reliability_snapshot_value(rows, jobs, now)
            {
              captured_at: now.dup.freeze,
              circuit_breakers: CircuitBreakerSnapshotBuilder.new(
                store:,
                rows:,
                jobs:,
                now:,
                operation: self
              ).to_h,
              stuck_jobs: StuckJobsSnapshotBuilder.new(rows:, jobs:).to_h
            }.freeze
          end

          def apply_recovery_to_rows(rows, recovery)
            RecoveredSnapshotRowsBuilder.new(rows:, recovery:, now: request.fetch(:now)).build
          end
        end

        # Placeholder operation for workflow methods not rebuilt on the durable engine yet.
        class Unsupported < Operation
          def initialize(operation_name:, **)
            super(**)
            @operation_name = operation_name
          end

          def call(context: _context)
            raise NotImplementedError,
                  "row-native durable operation #{operation_name.inspect} is not implemented yet"
          end

          private

          attr_reader :operation_name
        end

        %i[
          EnqueueWorkflow
          WorkflowSnapshot
          WorkflowHistory
          QueryWorkflow
          DeliverWorkflowSignal
          DeliverWorkflowEvent
          PauseWorkflow
          ResumeWorkflow
          ApproveWorkflowCheckpoints
          RejectWorkflowCheckpoints
          EnqueueChildWorkflow
          SyncChildWorkflows
          RollbackWorkflow
          RetryWorkflowSteps
          DeadLetterWorkflowSteps
          ReplayWorkflowSteps
          RetryDeadLetterWorkflowSteps
          DiscardWorkflowSteps
        ].each do |name|
          const_set(name, Class.new(Unsupported))
        end
      end
    end
  end
end
