# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Internal mutable state for the single-process queue store.
        class StoreState
          MAX_TRACKED_FAIR_QUEUE_LISTS = 128

          attr_reader :executions_by_token,
                      :batches_by_id,
                      :breaker_failures_by_scope,
                      :breaker_states_by_scope,
                      :execution_tokens_in_order,
                      :expired_reservation_tokens,
                      :expired_reservation_tokens_in_order,
                      :execution_tokens_by_job_id,
                      :half_open_probe_admissions_by_scope,
                      :jobs_by_id,
                      :last_reserved_queue_by_subscription,
                      :paused_queues,
                      :rate_limit_admissions_by_key,
                      :queued_job_ids_by_queue,
                      :retry_pending_job_ids,
                      :reservation_tokens_by_job_id,
                      :reservation_tokens_in_order,
                      :reservations_by_token,
                      :stuck_job_recoveries_by_id,
                      :workflow_children,
                      :workflow_dependency_job_ids_by_job_id,
                      :workflow_rollback_batch_ids,
                      :workflow_registrations_by_batch_id,
                      :workflow_rollbacks_by_batch_id

          # Immutable owner-local workflow registration metadata for one batch.
          WorkflowRegistration = Struct.new(
            :workflow_id,
            :step_job_ids,
            :dependency_job_ids_by_job_id,
            :compensation_jobs_by_step_id,
            :child_workflow_ids_by_step_id
          )
          # Immutable owner-local rollback metadata for one workflow batch.
          WorkflowRollback = Struct.new(:batch_id, :rollback_batch_id, :reason, :requested_at, :compensation_job_ids)

          # Owner-local child workflow relationship registry.
          class WorkflowChildren
            # Immutable owner-local child workflow relationship metadata.
            Relationship = Struct.new(
              :parent_workflow_id,
              :parent_batch_id,
              :parent_step_id,
              :parent_job_id,
              :child_workflow_id,
              :child_batch_id
            )
            private_constant :Relationship

            def initialize
              @by_child_batch_id = {}
              @by_parent_batch_id = {}
              @by_parent_job_id = {}
              @expected_child_workflow_id_by_job_id = {}
            end

            attr_reader :expected_child_workflow_id_by_job_id

            def register_expected_child(parent_job_id, child_workflow_id)
              expected_child_workflow_id_by_job_id[parent_job_id] = child_workflow_id
            end

            def register(parent_workflow_id:, parent_batch_id:, parent_step_id:, parent_job_id:, child_workflow_id:, child_batch_id:)
              relationship = Relationship.new(
                parent_workflow_id,
                parent_batch_id,
                parent_step_id,
                parent_job_id,
                child_workflow_id,
                child_batch_id
              ).freeze
              ensure_parent_relationships(parent_batch_id)[parent_step_id] = relationship
              @by_parent_job_id[parent_job_id] = relationship
              @by_child_batch_id[child_batch_id] = relationship
              relationship
            end

            def for_parent_step(parent_batch_id, parent_step_id)
              parent_relationships(parent_batch_id)[parent_step_id]
            end

            def for_parent_batch(parent_batch_id)
              parent_relationships(parent_batch_id).values
            end

            def for_parent_job(parent_job_id)
              @by_parent_job_id[parent_job_id]
            end

            def for_child_batch(child_batch_id)
              @by_child_batch_id[child_batch_id]
            end

            def delete_by_parent_batch(parent_batch_id)
              relationships = @by_parent_batch_id.delete(parent_batch_id)
              return [] unless relationships

              relationships.each_value.map do |relationship|
                delete_relationship(relationship, remove_parent_batch: false)
              end
            end

            def delete_by_child_batch(child_batch_id)
              relationship = @by_child_batch_id[child_batch_id]
              return unless relationship

              delete_relationship(relationship)
            end

            def delete_expected_children(parent_job_ids)
              parent_job_ids.each { |parent_job_id| @expected_child_workflow_id_by_job_id.delete(parent_job_id) }
            end

            private

            def parent_relationships(parent_batch_id)
              @by_parent_batch_id[parent_batch_id] || {}
            end

            def ensure_parent_relationships(parent_batch_id)
              @by_parent_batch_id[parent_batch_id] ||= {}
            end

            def delete_relationship(relationship, remove_parent_batch: true)
              child_batch_id = relationship.child_batch_id
              parent_job_id = relationship.parent_job_id
              parent_batch_id = relationship.parent_batch_id
              parent_step_id = relationship.parent_step_id

              @by_child_batch_id.delete(child_batch_id)
              @by_parent_job_id.delete(parent_job_id)
              @expected_child_workflow_id_by_job_id.delete(parent_job_id)
              return relationship unless remove_parent_batch

              relationships = @by_parent_batch_id[parent_batch_id]
              return relationship unless relationships

              relationships.delete(parent_step_id)
              @by_parent_batch_id.delete(parent_batch_id) if relationships.empty?
              relationship
            end
          end

          # Decides whether a terminal child batch must remain because its parent is still active.
          class ChildBatchRetention
            def initialize(batches_by_id:, workflow_children:, terminal_batch:)
              @batches_by_id = batches_by_id
              @workflow_children = workflow_children
              @terminal_batch = terminal_batch
            end

            def retain?(batch_id)
              relationship = workflow_children.for_child_batch(batch_id)
              return false unless relationship

              parent_batch = batches_by_id[relationship.parent_batch_id]
              parent_batch && !terminal_batch.call(parent_batch)
            end

            private

            attr_reader :batches_by_id, :terminal_batch, :workflow_children
          end

          # Prunes terminal batches while respecting active parent-child relationships.
          class TerminalBatchPruner
            def initialize(batch_indexes:, workflow_indexes:)
              @batch_indexes = batch_indexes
              @workflow_indexes = workflow_indexes
            end

            def call(retention_limit:, child_batch_retention:)
              pruned_batch_ids = []
              inspected_batch_count = 0

              loop do
                terminal_batch_count = terminal_batch_ids_in_order.length
                break unless terminal_batch_count > retention_limit && inspected_batch_count < terminal_batch_count

                batch_id = terminal_batch_ids_in_order.shift
                if child_batch_retention.retain?(batch_id)
                  terminal_batch_ids_in_order << batch_id
                  inspected_batch_count += 1
                  next
                end

                inspected_batch_count = 0
                terminal_batch_ids_index.delete(batch_id)
                batch = batches_by_id.delete(batch_id)
                if batch
                  cleanup_batch(batch_id:, batch:)
                  pruned_batch_ids << batch_id
                else
                  cleanup_batch(batch_id:, batch: nil)
                end
              end

              pruned_batch_ids
            end

            private

            attr_reader :batch_indexes, :workflow_indexes

            def batch_id_by_job_id
              batch_indexes.fetch(:batch_id_by_job_id)
            end

            def batches_by_id
              batch_indexes.fetch(:batches_by_id)
            end

            def terminal_batch_ids_in_order
              batch_indexes.fetch(:terminal_batch_ids_in_order)
            end

            def terminal_batch_ids_index
              batch_indexes.fetch(:terminal_batch_ids_index)
            end

            def workflow_children
              workflow_indexes.fetch(:workflow_children)
            end

            def workflow_dependency_job_ids_by_job_id
              workflow_indexes.fetch(:workflow_dependency_job_ids_by_job_id)
            end

            def workflow_registrations_by_batch_id
              workflow_indexes.fetch(:workflow_registrations_by_batch_id)
            end

            def workflow_rollback_batch_ids
              workflow_indexes.fetch(:workflow_rollback_batch_ids)
            end

            def workflow_rollbacks_by_batch_id
              workflow_indexes.fetch(:workflow_rollbacks_by_batch_id)
            end

            def cleanup_batch(batch_id:, batch:)
              PrunedBatchCleanup.call(
                batch_id:,
                batch:,
                job_indexes: {
                  batch_id_by_job_id:,
                  workflow_dependency_job_ids_by_job_id:
                },
                workflow_indexes: {
                  workflow_children:,
                  workflow_rollback_batch_ids:,
                  workflow_registrations_by_batch_id:,
                  workflow_rollbacks_by_batch_id:
                }
              )
            end
          end

          # Workflow registration writers kept separate from generic store state.
          module WorkflowMetadata
            def register_workflow(
              batch_id:,
              workflow_id:,
              step_job_ids:,
              dependency_job_ids_by_job_id:,
              compensation_jobs_by_step_id:,
              child_workflow_ids_by_step_id: {}
            )
              registration = WorkflowRegistration.new(
                workflow_id,
                step_job_ids.dup.freeze,
                dependency_job_ids_by_job_id.transform_values { |dependency_job_ids| dependency_job_ids.dup.freeze }.freeze,
                compensation_jobs_by_step_id.dup.freeze,
                child_workflow_ids_by_step_id.dup.freeze
              ).freeze
              workflow_registrations_by_batch_id[batch_id] = registration
              child_workflow_ids_by_step_id.each do |step_id, child_workflow_id|
                workflow_children.register_expected_child(step_job_ids.fetch(step_id), child_workflow_id)
              end
              registration
            end

            def register_workflow_dependencies(dependency_job_ids_by_job_id)
              workflow_dependency_job_ids_by_job_id.merge!(
                dependency_job_ids_by_job_id.transform_values { |dependency_job_ids| dependency_job_ids.dup.freeze }
              )
            end

            def workflow_dependency_job_ids_for(job_id)
              workflow_dependency_job_ids_by_job_id[job_id]
            end

            def register_workflow_rollback(batch_id:, rollback_batch_id:, reason:, requested_at:, compensation_job_ids:)
              workflow_rollback_batch_ids[rollback_batch_id] = true
              workflow_rollbacks_by_batch_id[batch_id] = WorkflowRollback.new(
                batch_id,
                rollback_batch_id,
                reason,
                requested_at,
                compensation_job_ids.dup.freeze
              ).freeze
            end
          end

          include WorkflowMetadata

          private_constant :ChildBatchRetention,
                           :TerminalBatchPruner,
                           :WorkflowChildren,
                           :WorkflowMetadata,
                           :WorkflowRegistration,
                           :WorkflowRollback

          def initialize(expired_tombstone_limit:)
            @batches_by_id = {}
            @batch_id_by_job_id = {}
            @breaker_failures_by_scope = {}
            @breaker_states_by_scope = {}
            @executions_by_token = {}
            @execution_tokens_in_order = []
            @expired_reservation_tokens = {}
            @expired_reservation_tokens_in_order = []
            @expired_tombstone_limit = expired_tombstone_limit
            @execution_tokens_by_job_id = {}
            @half_open_probe_admissions_by_scope = {}
            @jobs_by_id = {}
            @last_reserved_queue_by_subscription = {}
            @paused_queues = {}
            @rate_limit_admissions_by_key = {}
            @queued_job_ids_by_queue = {}
            @retry_pending_job_ids = []
            @retry_pending_job_ids_index = {}
            @reservation_tokens_by_job_id = {}
            @reservation_tokens_in_order = []
            @reservations_by_token = {}
            @stuck_job_recoveries_by_id = {}
            @terminal_batch_ids_index = {}
            @terminal_batch_ids_in_order = []
            @workflow_children = WorkflowChildren.new
            @workflow_dependency_job_ids_by_job_id = {}
            @workflow_rollback_batch_ids = {}
            @workflow_registrations_by_batch_id = {}
            @workflow_rollbacks_by_batch_id = {}
          end

          def queue_job_ids_for(queue)
            queued_job_ids_by_queue[queue] ||= []
          end

          def delete_queue(queue)
            queued_job_ids_by_queue.delete(queue)
          end

          def mark_queue_paused(queue, now)
            return :unchanged if paused_queues.key?(queue)

            paused_queues[queue] = now
            :changed
          end

          def unmark_queue_paused(queue)
            paused_queues.delete(queue) ? :changed : :unchanged
          end

          def queue_paused?(queue)
            paused_queues.key?(queue)
          end

          def last_reserved_queue_for(subscription_key)
            last_reserved_queue_by_subscription[subscription_key]
          end

          def record_reserved_queue(subscription_key, queue)
            last_reserved_queue_by_subscription.delete(subscription_key)
            last_reserved_queue_by_subscription[subscription_key] = queue
            trim_fair_queue_history
            queue
          end

          def register_retry_pending(job_id)
            unless @retry_pending_job_ids_index.key?(job_id)
              retry_pending_job_ids << job_id
              @retry_pending_job_ids_index[job_id] = true
            end

            retry_pending_job_ids
          end

          def delete_retry_pending(job_id)
            @retry_pending_job_ids_index.delete(job_id)
            retry_pending_job_ids.delete(job_id)
          end

          def rate_limit_admissions_for(key)
            rate_limit_admissions_by_key[key] ||= []
          end

          def breaker_failures_for(key)
            breaker_failures_by_scope[key] ||= []
          end

          def half_open_probe_admissions_for(key)
            half_open_probe_admissions_by_scope[key] ||= []
          end

          def delete_rate_limit_key(key)
            rate_limit_admissions_by_key.delete(key)
          end

          def clear_half_open_probe_admissions(key)
            half_open_probe_admissions_by_scope.delete(key)
          end

          def register_stuck_job_recovery(job_id:, now:, reason:)
            existing_recovery = stuck_job_recoveries_by_id[job_id]
            stuck_job_recoveries_by_id[job_id] = {
              recovery_count: existing_recovery ? existing_recovery.fetch(:recovery_count) + 1 : 1,
              last_recovered_at: now,
              last_recovery_reason: reason
            }
          end

          def reserve(reservation)
            reservation_token = reservation.token
            reservations_by_token[reservation_token] = reservation
            reservation_tokens_by_job_id[reservation.job_id] = reservation_token
            reservation_tokens_in_order << reservation_token
          end

          def activate_execution(reservation_token, reservation)
            delete_reservation_token(reservation_token)
            executions_by_token[reservation_token] = reservation
            execution_tokens_by_job_id[reservation.job_id] = reservation_token
            execution_tokens_in_order << reservation_token
          end

          def reservation_token_for_job(job_id)
            reservation_tokens_by_job_id[job_id]
          end

          def execution_token_for_job(job_id)
            execution_tokens_by_job_id[job_id]
          end

          def delete_reservation_token(reservation_token)
            reservation = reservations_by_token.delete(reservation_token)
            reservation_tokens_by_job_id.delete(reservation.job_id) if reservation
            reservation_index = reservation_tokens_in_order.index(reservation_token)
            reservation_tokens_in_order.delete_at(reservation_index) if reservation_index
          end

          def delete_execution_token(reservation_token)
            reservation = executions_by_token.delete(reservation_token)
            execution_tokens_by_job_id.delete(reservation.job_id) if reservation
            execution_index = execution_tokens_in_order.index(reservation_token)
            execution_tokens_in_order.delete_at(execution_index) if execution_index
          end

          def mark_expired(reservation_token)
            return if expired_reservation_tokens.key?(reservation_token)

            expired_reservation_tokens[reservation_token] = true
            expired_reservation_tokens_in_order << reservation_token
            prune_expired_reservation_tokens
          end

          def reservation_token_in_use?(reservation_token)
            reservations_by_token.key?(reservation_token) ||
              executions_by_token.key?(reservation_token) ||
              expired_reservation_tokens.key?(reservation_token)
          end

          def register_batch(batch)
            batch_id = batch.id
            batches_by_id[batch_id] = batch
            batch.job_ids.each { |job_id| @batch_id_by_job_id[job_id] = batch_id }
            if terminal_batch?(batch) && !@terminal_batch_ids_index[batch_id]
              @terminal_batch_ids_index[batch_id] = true
              @terminal_batch_ids_in_order << batch_id
            end
            batch
          end

          def prune_terminal_batches(retention_limit, changed_job: nil)
            if changed_job
              batch_id = @batch_id_by_job_id[changed_job.id]
              return [] unless batch_id

              track_terminal_batch(batch_id)
            end

            child_batch_retention = ChildBatchRetention.new(
              batches_by_id:,
              workflow_children:,
              terminal_batch: method(:terminal_batch?)
            )
            TerminalBatchPruner.new(
              batch_indexes: {
                terminal_batch_ids_in_order: @terminal_batch_ids_in_order,
                terminal_batch_ids_index: @terminal_batch_ids_index,
                batches_by_id:,
                batch_id_by_job_id: @batch_id_by_job_id
              },
              workflow_indexes: {
                workflow_dependency_job_ids_by_job_id:,
                workflow_children:,
                workflow_rollback_batch_ids:,
                workflow_registrations_by_batch_id:,
                workflow_rollbacks_by_batch_id:
              }
            ).call(retention_limit:, child_batch_retention:)
          end

          private

          def track_terminal_batch(batch_id)
            batch = batches_by_id[batch_id]
            return unless batch

            batch_terminal = terminal_batch?(batch)
            batch_tracked = @terminal_batch_ids_index[batch_id]
            case [batch_terminal, batch_tracked]
            when [true, false], [true, nil]
              @terminal_batch_ids_index[batch_id] = true
              @terminal_batch_ids_in_order << batch_id
            when [false, true]
              @terminal_batch_ids_index[batch_id] = false
              @terminal_batch_ids_in_order.delete(batch_id)
            end
          end

          def terminal_batch?(batch)
            batch.job_ids.all? do |job_id|
              job = jobs_by_id[job_id]
              job&.terminal?
            end
          end

          # Removes indexes owned by a pruned workflow or plain batch.
          class PrunedBatchCleanup
            def self.call(**)
              new(**).call
            end

            def initialize(
              batch_id:,
              batch:,
              job_indexes:,
              workflow_indexes:
            )
              @batch_id = batch_id
              @batch = batch
              @job_indexes = job_indexes
              @workflow_indexes = workflow_indexes
            end

            def call
              pruned_job_ids ? cleanup_batch_jobs : cleanup_stale_batch_membership
              cleanup_workflow_registration
            end

            private

            attr_reader :batch,
                        :batch_id,
                        :job_indexes,
                        :workflow_indexes

            def pruned_job_ids
              batch&.job_ids
            end

            def cleanup_batch_jobs
              pruned_job_ids.each do |job_id|
                batch_id_by_job_id.delete(job_id)
                workflow_dependency_job_ids_by_job_id.delete(job_id)
              end
            end

            def cleanup_stale_batch_membership
              stale_job_ids = batch_id_by_job_id.each_with_object([]) do |(job_id, stored_batch_id), job_ids|
                job_ids << job_id if stored_batch_id == batch_id
              end

              stale_job_ids.each do |job_id|
                batch_id_by_job_id.delete(job_id)
                workflow_dependency_job_ids_by_job_id.delete(job_id)
              end
            end

            def cleanup_workflow_registration
              registration = workflow_registrations_by_batch_id.delete(batch_id)
              rollback = workflow_rollbacks_by_batch_id.delete(batch_id)
              cleanup_child_workflows(registration)
              workflow_rollback_batch_ids.delete(rollback.rollback_batch_id) if rollback
              registration
            end

            def cleanup_child_workflows(registration)
              cleanup_expected_children(registration)
              workflow_children.delete_by_parent_batch(batch_id)
              workflow_children.delete_by_child_batch(batch_id)
            end

            def cleanup_expected_children(registration)
              ExpectedChildrenCleanup.new(registration, workflow_children).call
            end

            # Deletes declared child markers for a registration even when no child relationship exists.
            class ExpectedChildrenCleanup
              def initialize(registration, workflow_children)
                @registration = registration
                @workflow_children = workflow_children
              end

              def call
                return unless registration

                workflow_children.delete_expected_children(
                  registration.child_workflow_ids_by_step_id.keys.map do |step_id|
                    registration.step_job_ids.fetch(step_id)
                  end
                )
              end

              private

              attr_reader :registration, :workflow_children
            end
            private_constant :ExpectedChildrenCleanup

            def batch_id_by_job_id
              job_indexes.fetch(:batch_id_by_job_id)
            end

            def workflow_dependency_job_ids_by_job_id
              job_indexes.fetch(:workflow_dependency_job_ids_by_job_id)
            end

            def workflow_rollback_batch_ids
              workflow_indexes.fetch(:workflow_rollback_batch_ids)
            end

            def workflow_children
              workflow_indexes.fetch(:workflow_children)
            end

            def workflow_registrations_by_batch_id
              workflow_indexes.fetch(:workflow_registrations_by_batch_id)
            end

            def workflow_rollbacks_by_batch_id
              workflow_indexes.fetch(:workflow_rollbacks_by_batch_id)
            end
          end
          private_constant :PrunedBatchCleanup

          def trim_fair_queue_history
            last_reserved_queue_by_subscription.shift while last_reserved_queue_by_subscription.length > MAX_TRACKED_FAIR_QUEUE_LISTS
          end

          def prune_expired_reservation_tokens
            while expired_reservation_tokens_in_order.length > @expired_tombstone_limit
              oldest_token = expired_reservation_tokens_in_order.shift
              expired_reservation_tokens.delete(oldest_token)
            end
          end
        end
      end
    end
  end
end
