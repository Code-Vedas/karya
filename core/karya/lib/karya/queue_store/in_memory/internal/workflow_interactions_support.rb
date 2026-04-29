# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class InMemory
      module Internal
        # Owner-local workflow query and interaction delivery support.
        module WorkflowSupport
          def query_workflow(batch_id:, query:, now:)
            normalized_now = normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)
            normalized_batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)

            @mutex.synchronize do
              recover_in_flight_locked(normalized_now)
              batch = fetch_batch(normalized_batch_id)
              registration = fetch_workflow_registration(batch.id)
              jobs = fetch_batch_jobs(batch)
              snapshot = build_workflow_snapshot(batch:, registration:, jobs:, now: normalized_now)
              WorkflowQuery.new(snapshot:, query:, queried_at: normalized_now).to_result
            end
          end

          def deliver_workflow_signal(batch_id:, signal:, payload:, now:)
            deliver_workflow_interaction(
              action: :deliver_workflow_signal,
              batch_id:,
              name: signal,
              payload:,
              now:,
              kind: :signal
            )
          end

          def deliver_workflow_event(batch_id:, event:, payload:, now:)
            deliver_workflow_interaction(
              action: :deliver_workflow_event,
              batch_id:,
              name: event,
              payload:,
              now:,
              kind: :event
            )
          end

          private

          def deliver_workflow_interaction(action:, batch_id:, name:, payload:, now:, kind:)
            normalized_now = normalize_time(:now, now, error_class: Workflow::InvalidExecutionError)
            normalized_batch_id = Workflow.send(:normalize_batch_identifier, :batch_id, batch_id)
            interaction = Workflow::InteractionSnapshot.new(kind:, name:, payload:, received_at: normalized_now)
            interaction_kind = interaction.kind
            signal_interaction = interaction_kind == :signal
            interaction_name = interaction.name
            interaction_action = signal_interaction ? :signal_delivered : :event_delivered

            @mutex.synchronize do
              recover_in_flight_locked(normalized_now)
              batch = fetch_batch(normalized_batch_id)
              workflow_batch_id = batch.id
              registration = fetch_workflow_registration(workflow_batch_id)
              jobs = fetch_batch_jobs(batch)
              snapshot = build_workflow_snapshot(batch:, registration:, jobs:, now: normalized_now)
              validate_workflow_interaction_delivery(snapshot, workflow_batch_id)
              validate_workflow_interaction_support(registration, interaction_kind, interaction_name, workflow_batch_id)
              state.register_workflow_interaction(batch_id: workflow_batch_id, interaction:)
              state.register_workflow_history_entry(
                batch_id: workflow_batch_id,
                kind: :interaction,
                action: interaction_action,
                occurred_at: normalized_now,
                details: {
                  'name' => interaction_name,
                  'payload' => interaction.payload
                }
              )
              auto_approve_matching_checkpoints(registration, signal_name: interaction_name, decided_at: normalized_now) if signal_interaction
              BulkMutationReport.new(
                action:,
                performed_at: normalized_now,
                requested_job_ids: [],
                changed_jobs: [],
                skipped_jobs: []
              )
            end
          end

          def validate_workflow_interaction_delivery(snapshot, batch_id)
            return unless WORKFLOW_INTERACTION_TERMINAL_STATES.include?(snapshot.state)

            raise Workflow::InvalidExecutionError, "workflow batch #{batch_id.inspect} is terminal and cannot receive interactions"
          end

          def validate_workflow_interaction_support(registration, interaction_kind, interaction_name, batch_id)
            supported = SupportedInteraction.new(
              registration:,
              interaction_kind:,
              interaction_name:
            ).supported?
            return if supported

            raise Workflow::InvalidExecutionError,
                  "workflow batch #{batch_id.inspect} does not support #{interaction_kind} #{interaction_name.inspect}"
          end

          def auto_approve_matching_checkpoints(registration, signal_name:, decided_at:)
            registration.approval_requirements_by_job_id.each do |job_id, requirement|
              next unless requirement.fetch(:name) == signal_name

              state.register_workflow_approval_approved(job_id:, decided_at:)
            end
          end

          # Checks whether one delivered interaction is declared by the workflow.
          class SupportedInteraction
            def initialize(registration:, interaction_kind:, interaction_name:)
              @registration = registration
              @interaction_kind = interaction_kind
              @interaction_name = interaction_name
            end

            def supported?
              registration.interaction_supported_keys.key?([interaction_kind, interaction_name])
            end

            private

            attr_reader :interaction_kind, :interaction_name, :registration
          end
        end
      end
    end
  end
end
