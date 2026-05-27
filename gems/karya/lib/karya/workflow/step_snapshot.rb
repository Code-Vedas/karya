# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Workflow
    # Immutable inspection view for one workflow step at a point in time.
    class StepSnapshot
      WAITING_STATES = %i[queued submission].freeze

      attr_reader :child_workflow,
                  :child_workflow_id,
                  :job,
                  :prerequisite_job_ids,
                  :prerequisite_states

      def initialize(**attributes)
        attributes = Attributes.new(attributes)
        @identity = Identity.new(**attributes.identity_attributes)
        @job = attributes.job
        @prerequisite_job_ids = attributes.prerequisite_job_ids
        @prerequisite_states = PrerequisiteStates.new(
          prerequisite_job_ids: @prerequisite_job_ids,
          prerequisite_states: attributes.prerequisite_states
        ).to_h
        @child_workflow_id = attributes.child_workflow_id
        @child_workflow = ChildWorkflow.new(
          **attributes.child_workflow_attributes(
            child_workflow_id: @child_workflow_id,
            parent_batch_id: batch_id,
            parent_step_id: step_id,
            parent_job_id: job_id
          )
        ).to_snapshot
        @interaction = Interaction.new(**attributes.interaction_attributes)
        @approval = Approval.new(**attributes.approval_attributes)
        freeze
      end

      def workflow_id = identity.workflow_id

      def batch_id = identity.batch_id

      def step_id = identity.step_id

      def job_id = identity.job_id

      def state = job.state

      def interaction_kind = interaction.kind

      def interaction_name = interaction.name

      def interaction_received_at = interaction.received_at

      def approval_name = approval.name

      def approval_state = approval.state

      def approval_decided_at = approval.decided_at

      def approval_received_at = approval.received_at

      def approval_rejection_reason = approval.rejection_reason

      def ready?
        waiting? && prerequisites_succeeded? && child_workflow_succeeded? && interaction_satisfied? && approval_satisfied?
      end

      def blocked?
        waiting? && !ready?
      end

      def active?
        !terminal? && !waiting?
      end

      def terminal?
        job.terminal?
      end

      def child_workflow?
        !!child_workflow_id
      end

      def approval_step?
        !!approval_name
      end

      def awaiting_approval?
        approval_step? && waiting? && prerequisites_succeeded? && child_workflow_succeeded? && !approval_satisfied?
      end

      def approval_rejected?
        approval_state == :rejected
      end

      # Validates and exposes step snapshot construction attributes.
      class Attributes
        REQUIRED_ATTRIBUTES = %i[
          workflow_id
          batch_id
          step_id
          job_id
          job
          prerequisite_job_ids
          prerequisite_states
        ].freeze
        OPTIONAL_ATTRIBUTES = %i[
          child_workflow_id
          child_workflow
          approval_name
          approval_state
          approval_decided_at
          approval_received_at
          approval_rejection_reason
          interaction_kind
          interaction_name
          interaction_received_at
        ].freeze
        SUPPORTED_ATTRIBUTES = (REQUIRED_ATTRIBUTES + OPTIONAL_ATTRIBUTES).freeze

        def initialize(attributes)
          @attributes = attributes
          validate_keys
        end

        def workflow_id
          Workflow.send(:normalize_identifier, :workflow_id, fetch(:workflow_id))
        end

        def identity_attributes
          {
            workflow_id:,
            batch_id:,
            step_id:,
            job_id:
          }
        end

        def batch_id
          Workflow.send(:normalize_batch_identifier, :batch_id, fetch(:batch_id))
        end

        def step_id
          Workflow.send(:normalize_execution_identifier, :step_id, fetch(:step_id))
        end

        def job_id
          Workflow.send(:normalize_execution_identifier, :job_id, fetch(:job_id))
        end

        def job
          JobEntry.new(job_id:, job: fetch(:job)).to_job
        end

        def prerequisite_job_ids
          JobIdList.new(:prerequisite_job_id, fetch(:prerequisite_job_ids)).to_a
        end

        def prerequisite_states
          fetch(:prerequisite_states)
        end

        def child_workflow_id
          value = attributes.fetch(:child_workflow_id, nil)
          return unless value

          Workflow.send(:normalize_identifier, :child_workflow_id, value)
        end

        def child_workflow
          attributes.fetch(:child_workflow, nil)
        end

        def interaction_kind
          InteractionKindValue.new(attributes.fetch(:interaction_kind, nil)).to_sym
        end

        def interaction_name
          OptionalIdentifier.new(:interaction_name, attributes.fetch(:interaction_name, nil)).to_s
        end

        def interaction_received_at
          OptionalTimestamp.new(:interaction_received_at, attributes.fetch(:interaction_received_at, nil)).to_time
        end

        def approval_name
          OptionalIdentifier.new(:approval_name, attributes.fetch(:approval_name, nil)).to_s
        end

        def approval_state
          ApprovalStateValue.new(attributes.fetch(:approval_state, nil)).to_sym
        end

        def approval_decided_at
          OptionalTimestamp.new(:approval_decided_at, attributes.fetch(:approval_decided_at, nil)).to_time
        end

        def approval_received_at
          OptionalTimestamp.new(:approval_received_at, attributes.fetch(:approval_received_at, nil)).to_time
        end

        def approval_rejection_reason
          OptionalString.new(:approval_rejection_reason, attributes.fetch(:approval_rejection_reason, nil)).to_s
        end

        def child_workflow_attributes(child_workflow_id:, parent_batch_id:, parent_step_id:, parent_job_id:)
          {
            child_workflow:,
            child_workflow_id:,
            parent_batch_id:,
            parent_step_id:,
            parent_job_id:
          }
        end

        def interaction_attributes
          {
            kind: interaction_kind,
            name: interaction_name,
            received_at: interaction_received_at
          }
        end

        def approval_attributes
          {
            name: approval_name,
            state: approval_state,
            decided_at: approval_decided_at,
            received_at: approval_received_at,
            rejection_reason: approval_rejection_reason
          }
        end

        private

        attr_reader :attributes

        def fetch(name)
          attributes.fetch(name) { raise ArgumentError, "missing keyword: :#{name}" }
        end

        def validate_keys
          unknown_keys = attributes.keys - SUPPORTED_ATTRIBUTES
          return if unknown_keys.empty?

          raise ArgumentError, "unknown keyword: :#{unknown_keys.first}"
        end
      end

      # Validates optional child workflow relationship metadata.
      class ChildWorkflow
        def initialize(child_workflow:, child_workflow_id:, parent_batch_id:, parent_step_id:, parent_job_id:)
          @child_workflow = child_workflow
          @child_workflow_id = child_workflow_id
          @parent_batch_id = parent_batch_id
          @parent_step_id = parent_step_id
          @parent_job_id = parent_job_id
        end

        def to_snapshot
          return unless child_workflow
          raise InvalidExecutionError, 'child_workflow must be Karya::Workflow::ChildWorkflowSnapshot' unless child_workflow.is_a?(ChildWorkflowSnapshot)

          validate_identity
          child_workflow
        end

        private

        attr_reader :child_workflow, :child_workflow_id, :parent_batch_id, :parent_job_id, :parent_step_id

        def validate_identity
          raise InvalidExecutionError, 'child_workflow_id must match child workflow relationship' if child_workflow_id != child_workflow.child_workflow_id
          raise InvalidExecutionError, 'child workflow parent batch must match step batch' unless parent_batch_id == child_workflow.parent_batch_id
          raise InvalidExecutionError, 'child workflow parent step must match step id' unless parent_step_id == child_workflow.parent_step_id
          return if parent_job_id == child_workflow.parent_job_id

          raise InvalidExecutionError, 'child workflow parent job must match step job'
        end
      end

      # Groups the normalized identity fields for one step snapshot.
      class Identity
        attr_reader :batch_id, :job_id, :step_id, :workflow_id

        def initialize(workflow_id:, batch_id:, step_id:, job_id:)
          @workflow_id = workflow_id
          @batch_id = batch_id
          @step_id = step_id
          @job_id = job_id
          freeze
        end
      end

      # Validates the concrete job backing a step snapshot.
      class JobEntry
        def initialize(job_id:, job:)
          @job_id = job_id
          @job = job
        end

        def to_job
          raise InvalidExecutionError, 'job must be Karya::Job' unless job.is_a?(Job)
          return job if job.id == job_id

          raise InvalidExecutionError, 'job_id must match job id'
        end

        private

        attr_reader :job, :job_id
      end

      # Normalizes ordered job id lists.
      class JobIdList
        def initialize(field_name, job_ids)
          @field_name = field_name
          @job_ids = job_ids
        end

        def to_a
          raise InvalidExecutionError, "#{field_name}s must be an Array" unless job_ids.is_a?(Array)

          normalized_job_ids = job_ids.map do |job_id|
            Workflow.send(:normalize_execution_identifier, field_name, job_id)
          end
          duplicate_job_id = normalized_job_ids.tally.find { |_job_id, count| count > 1 }&.first
          raise InvalidExecutionError, "duplicate #{field_name} #{duplicate_job_id.inspect}" if duplicate_job_id

          normalized_job_ids.freeze
        end

        private

        attr_reader :field_name, :job_ids
      end

      # Normalizes prerequisite states keyed by prerequisite job id.
      class PrerequisiteStates
        def initialize(prerequisite_job_ids:, prerequisite_states:)
          @prerequisite_job_ids = prerequisite_job_ids
          @prerequisite_states = prerequisite_states
        end

        def to_h
          raise InvalidExecutionError, 'prerequisite_states must be a Hash' unless prerequisite_states.is_a?(Hash)

          normalized_states = prerequisite_states.each_with_object({}) do |(job_id, state), states|
            normalized_job_id = Workflow.send(:normalize_execution_identifier, :prerequisite_job_id, job_id)
            raise InvalidExecutionError, "duplicate prerequisite job #{normalized_job_id.inspect}" if states.key?(normalized_job_id)

            states[normalized_job_id] = normalize_state(state)
          end
          validate_membership(normalized_states)
          prerequisite_job_ids.to_h { |job_id| [job_id, normalized_states[job_id]] }.freeze
        end

        private

        attr_reader :prerequisite_job_ids, :prerequisite_states

        def normalize_state(state)
          case state
          when NilClass
            nil
          else
            JobLifecycle.validate_state!(state)
          end
        rescue JobLifecycle::InvalidJobStateError => e
          raise InvalidExecutionError, e.message, cause: e
        end

        def validate_membership(normalized_states)
          unknown_job_id = normalized_states.keys.find { |job_id| !prerequisite_job_ids.include?(job_id) }
          return unless unknown_job_id

          raise InvalidExecutionError, "unknown prerequisite job #{unknown_job_id.inspect}"
        end
      end

      # Groups one optional workflow interaction gate and its delivery state.
      class Interaction
        attr_reader :kind, :name, :received_at

        def initialize(kind:, name:, received_at:)
          @kind = kind
          @name = name
          @received_at = received_at
          validate_presence
          validate_timestamp_dependency
          freeze
        end

        private

        def validate_presence
          return if [kind, name].all?(&:nil?)
          return if [kind, name].none?(&:nil?)

          raise InvalidExecutionError, 'interaction_kind and interaction_name must both be present or both be nil'
        end

        def validate_timestamp_dependency
          return if [received_at].compact.empty?
          return if name

          raise InvalidExecutionError, 'interaction_received_at requires interaction_kind and interaction_name'
        end
      end

      # Groups one optional approval checkpoint and its decision state.
      class Approval
        attr_reader :decided_at, :name, :received_at, :rejection_reason, :state

        def initialize(name:, state:, decided_at:, received_at:, rejection_reason:)
          @name = name
          @state = state
          @decided_at = decided_at
          @received_at = received_at
          @rejection_reason = rejection_reason
          validate_presence
          validate_state_details
          freeze
        end

        private

        def validate_presence
          return if [name, state, decided_at, received_at, rejection_reason].compact.empty?
          return if name

          raise InvalidExecutionError, 'approval metadata requires approval_name'
        end

        def validate_state_details
          return unless name

          ValidationState.new(
            state:,
            decided_at:,
            received_at:,
            rejection_reason:,
            rejection_reason_error_message:
          ).validate
        end

        def rejection_reason_error_message
          'approval_rejection_reason requires approval_state :rejected'
        end

        # Validates approval metadata for one normalized approval state.
        class ValidationState
          def initialize(state:, decided_at:, received_at:, rejection_reason:, rejection_reason_error_message:)
            @state = state
            @decided_at = decided_at
            @received_at = received_at
            @rejection_reason = rejection_reason
            @rejection_reason_error_message = rejection_reason_error_message
          end

          def validate
            validator.validate
          end

          private

          attr_reader :decided_at, :received_at, :rejection_reason, :rejection_reason_error_message, :state

          def validator
            case state
            when :approved
              Approved.new(decided_at:, received_at:, rejection_reason:, rejection_reason_error_message:)
            when :rejected
              Rejected.new(decided_at:, received_at:, rejection_reason:)
            else
              Undecided.new(decided_at:, rejection_reason:, rejection_reason_error_message:)
            end
          end

          # Validates approval metadata for an approved checkpoint.
          class Approved
            def initialize(decided_at:, received_at:, rejection_reason:, rejection_reason_error_message:)
              @decided_at = decided_at
              @received_at = received_at
              @rejection_reason = rejection_reason
              @rejection_reason_error_message = rejection_reason_error_message
            end

            def validate
              raise InvalidExecutionError, 'approval_state :approved requires approval_decided_at' unless decided_at
              raise InvalidExecutionError, rejection_reason_error_message if rejection_reason
              raise InvalidExecutionError, 'approval_state :approved requires approval_received_at' unless received_at
            end

            private

            attr_reader :decided_at, :received_at, :rejection_reason, :rejection_reason_error_message
          end

          # Validates approval metadata for a rejected checkpoint.
          class Rejected
            def initialize(decided_at:, received_at:, rejection_reason:)
              @decided_at = decided_at
              @received_at = received_at
              @rejection_reason = rejection_reason
            end

            def validate
              raise InvalidExecutionError, 'approval_state :rejected requires approval_decided_at' unless decided_at
              raise InvalidExecutionError, 'approval_state :rejected must not include approval_received_at' if received_at
              raise InvalidExecutionError, 'approval_state :rejected requires approval_rejection_reason' unless rejection_reason
            end

            private

            attr_reader :decided_at, :received_at, :rejection_reason
          end

          # Validates approval metadata for an undecided checkpoint.
          class Undecided
            def initialize(decided_at:, rejection_reason:, rejection_reason_error_message:)
              @decided_at = decided_at
              @rejection_reason = rejection_reason
              @rejection_reason_error_message = rejection_reason_error_message
            end

            def validate
              raise InvalidExecutionError, 'approval_decided_at requires approval_state' if decided_at
              raise InvalidExecutionError, rejection_reason_error_message if rejection_reason
            end

            private

            attr_reader :decided_at, :rejection_reason, :rejection_reason_error_message
          end

          private_constant :Approved, :Rejected, :Undecided
        end

        private_constant :ValidationState
      end

      # Normalizes one optional approval state.
      class ApprovalStateValue
        def initialize(value)
          @value = value
        end

        def to_sym
          return nil unless value

          raise_invalid_state unless value.is_a?(String) || value.is_a?(Symbol)

          state = value.to_sym
          return state if %i[approved rejected].include?(state)

          raise_invalid_state
        end

        private

        attr_reader :value

        def raise_invalid_state
          raise InvalidExecutionError, 'approval_state must be :approved or :rejected'
        end
      end

      # Normalizes one optional interaction kind.
      class InteractionKindValue
        def initialize(value)
          @value = value
        end

        def to_sym
          return nil unless value

          raise_invalid_kind unless value.is_a?(String) || value.is_a?(Symbol)

          kind = value.to_sym
          return kind if %i[signal event].include?(kind)

          raise_invalid_kind
        end

        private

        attr_reader :value

        def raise_invalid_kind
          raise InvalidExecutionError, 'interaction_kind must be :signal or :event'
        end
      end

      # Normalizes one optional identifier field.
      class OptionalIdentifier
        def initialize(field_name, value)
          @field_name = field_name
          @value = value
        end

        def to_s
          return nil unless value

          normalize_execution_identifier
        end

        private

        attr_reader :field_name, :value

        def normalize_execution_identifier
          Workflow.send(:normalize_execution_identifier, field_name, value)
        end
      end

      # Normalizes one optional plain String field.
      class OptionalString
        def initialize(field_name, value)
          @field_name = field_name
          @value = value
        end

        def to_s
          return nil unless value
          raise InvalidExecutionError, "#{field_name} must be a String" unless value.is_a?(String)

          normalized = value.strip
          raise InvalidExecutionError, "#{field_name} must be present" if normalized.empty?

          normalized.freeze
        end

        private

        attr_reader :field_name, :value
      end

      # Normalizes one optional timestamp field.
      class OptionalTimestamp
        def initialize(field_name, value)
          @field_name = field_name
          @value = value
        end

        def to_time
          return nil unless value

          Timestamp.new(field_name, value).to_time
        end

        private

        attr_reader :field_name, :value
      end

      # Normalizes timestamps into immutable values.
      class Timestamp
        def initialize(name, value)
          @name = name
          @value = value
        end

        def to_time
          return value.dup.freeze if value.is_a?(Time)

          raise InvalidExecutionError, "#{name} must be a Time"
        end

        private

        attr_reader :name, :value
      end

      private_constant :Approval,
                       :ApprovalStateValue,
                       :Attributes,
                       :ChildWorkflow,
                       :Identity,
                       :Interaction,
                       :InteractionKindValue,
                       :JobEntry,
                       :JobIdList,
                       :OptionalIdentifier,
                       :OptionalString,
                       :OptionalTimestamp,
                       :PrerequisiteStates,
                       :Timestamp,
                       :WAITING_STATES

      private

      attr_reader :approval, :identity, :interaction

      def waiting?
        WAITING_STATES.include?(state)
      end

      def prerequisites_succeeded?
        prerequisite_job_ids.all? { |prerequisite_job_id| prerequisite_states.fetch(prerequisite_job_id) == :succeeded }
      end

      def child_workflow_succeeded?
        return true unless child_workflow_id
        return false unless child_workflow

        child_workflow.child_state == :succeeded
      end

      def interaction_satisfied?
        interaction_name ? !!interaction_received_at : true
      end

      def approval_satisfied?
        return true unless approval_name
        return false if approval_rejected?

        !!approval_received_at
      end
    end
  end
end
