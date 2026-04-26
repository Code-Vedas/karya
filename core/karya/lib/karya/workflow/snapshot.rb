# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Workflow
    # Immutable inspection view for one workflow run at a point in time.
    class Snapshot
      FAILED_STATES = %i[failed dead_letter].freeze
      COMPLETED_STATES = %i[succeeded cancelled].freeze
      WAITING_STATES = %i[queued submission].freeze
      REQUIRED_ATTRIBUTES = %i[
        workflow_id
        batch_id
        captured_at
        step_job_ids
        dependency_job_ids_by_job_id
        jobs
      ].freeze
      OPTIONAL_ATTRIBUTES = %i[
        child_workflow_ids_by_step_id
        child_workflows
        interactions
        interaction_requirements_by_job_id
        parent
        rollback
      ].freeze
      SUPPORTED_ATTRIBUTES = (REQUIRED_ATTRIBUTES + OPTIONAL_ATTRIBUTES).freeze

      def initialize(**attributes)
        attributes = Attributes.new(attributes)
        @identity = attributes.identity
        @membership = attributes.membership
        @child_relationships = attributes.child_relationships
        @interactions = attributes.interactions
        grouped_interactions = interactions.group_by(&:kind)
        @signals = grouped_interactions.fetch(:signal, []).freeze
        @events = grouped_interactions.fetch(:event, []).freeze
        @step_inspection = StepInspection.new(
          identity:,
          membership:,
          child_relationships:,
          interaction_requirements_by_job_id: attributes.interaction_requirements_by_job_id,
          interactions:
        )
        @parent = attributes.parent
        @rollback = attributes.rollback
        @summary_data = SummaryData.new(membership, step_inspection)
        freeze
      end

      def workflow_id
        identity.workflow_id
      end

      def batch_id
        identity.batch_id
      end

      def captured_at
        identity.captured_at
      end

      def job_ids
        membership.job_ids
      end

      def jobs
        membership.jobs
      end

      def step_states
        membership.step_states
      end

      def steps
        step_inspection.steps
      end

      def step(step_id)
        step_inspection.step(step_id)
      end

      def fetch_step(step_id)
        step_inspection.fetch_step(step_id)
      end

      def job_for_step(step_id)
        fetch_step(step_id).job
      end

      def job_id_for_step(step_id)
        fetch_step(step_id).job_id
      end

      def state_for_step(step_id)
        fetch_step(step_id).state
      end

      def rollback_requested?
        !!rollback
      end

      def child_workflows
        child_relationships.child_workflows
      end

      def child_workflow(step_id)
        child_relationships.child_workflow(step_id)
      end

      def fetch_child_workflow(step_id)
        child_relationships.fetch_child_workflow(step_id)
      end

      attr_reader :events, :interactions, :parent, :rollback, :signals

      def state_counts
        summary_data.state_counts
      end

      def total_count
        summary_data.total_count
      end

      def completed_count
        summary_data.completed_count
      end

      def failed_count
        summary_data.failed_count
      end

      def state
        summary_data.state
      end

      # Validates and exposes snapshot construction attributes.
      class Attributes
        def initialize(attributes)
          @attributes = attributes
          validate_keys
        end

        def fetch(name)
          attributes.fetch(name) { raise ArgumentError, "missing keyword: :#{name}" }
        end

        def identity
          Identity.new(
            workflow_id: Workflow.send(:normalize_identifier, :workflow_id, fetch(:workflow_id)),
            batch_id: Workflow.send(:normalize_batch_identifier, :batch_id, fetch(:batch_id)),
            captured_at: Timestamp.new(:captured_at, fetch(:captured_at)).to_time
          )
        end

        def membership
          Membership.new(
            step_job_ids: StepJobIds.new(fetch(:step_job_ids)).to_h,
            dependency_job_ids_by_job_id: DependencyJobIds.new(fetch(:dependency_job_ids_by_job_id)).to_h,
            jobs: JobList.new(fetch(:jobs)).to_a
          )
        end

        def rollback
          value = attributes.fetch(:rollback, nil)
          raise InvalidExecutionError, 'rollback must be Karya::Workflow::RollbackSnapshot' if value && !value.is_a?(RollbackSnapshot)

          value
        end

        def child_relationships
          ChildRelationships.new(
            child_workflow_ids_by_step_id: ChildWorkflowIds.new(attributes.fetch(:child_workflow_ids_by_step_id, {})).to_h,
            child_workflows: ChildWorkflowList.new(attributes.fetch(:child_workflows, [])).to_a
          )
        end

        def interactions
          InteractionList.new(attributes.fetch(:interactions, [])).to_a
        end

        def interaction_requirements_by_job_id
          InteractionRequirements.new(attributes.fetch(:interaction_requirements_by_job_id, {})).to_h
        end

        def parent
          value = attributes.fetch(:parent, nil)
          raise InvalidExecutionError, 'parent must be Karya::Workflow::ChildWorkflowSnapshot' if value && !value.is_a?(ChildWorkflowSnapshot)

          value
        end

        private

        attr_reader :attributes

        def validate_keys
          unknown_keys = attributes.keys - SUPPORTED_ATTRIBUTES
          return if unknown_keys.empty?

          raise ArgumentError, "unknown keyword: :#{unknown_keys.first}"
        end
      end

      # Groups normalized parent and child workflow relationship metadata.
      class ChildRelationships
        attr_reader :child_workflow_ids_by_step_id, :child_workflows, :child_workflows_by_step_id

        def initialize(child_workflow_ids_by_step_id:, child_workflows:)
          @child_workflow_ids_by_step_id = child_workflow_ids_by_step_id
          @child_workflows = child_workflows
          validate_relationships
          @child_workflows_by_step_id = child_workflows.to_h { |child_workflow| [child_workflow.parent_step_id, child_workflow] }.freeze
          freeze
        end

        def child_workflow_id(step_id)
          normalized_step_id = Workflow.send(:normalize_execution_identifier, :step_id, step_id)
          child_workflow_ids_by_step_id[normalized_step_id]
        end

        def child_workflow(step_id)
          normalized_step_id = Workflow.send(:normalize_execution_identifier, :step_id, step_id)
          child_workflows_by_step_id[normalized_step_id]
        end

        def fetch_child_workflow(step_id)
          normalized_step_id = Workflow.send(:normalize_execution_identifier, :step_id, step_id)
          child_workflows_by_step_id.fetch(normalized_step_id) do
            raise InvalidExecutionError, "unknown child workflow for step #{normalized_step_id.inspect}"
          end
        end

        private

        def validate_relationships
          seen_parent_step_ids = {}

          child_workflows.each do |child_workflow|
            parent_step_id = child_workflow.parent_step_id
            inspected_parent_step_id = parent_step_id.inspect
            raise InvalidExecutionError, "duplicate child workflow for step #{inspected_parent_step_id}" if seen_parent_step_ids.key?(parent_step_id)

            seen_parent_step_ids[parent_step_id] = true
            expected_workflow_id = child_workflow_ids_by_step_id[parent_step_id]
            raise InvalidExecutionError, "unknown child workflow step #{inspected_parent_step_id}" unless expected_workflow_id
            next if expected_workflow_id == child_workflow.child_workflow_id

            raise InvalidExecutionError, 'child workflow relationship id must match declared child workflow id'
          end
        end
      end

      # Groups normalized snapshot identity fields.
      class Identity
        attr_reader :batch_id, :captured_at, :workflow_id

        def initialize(workflow_id:, batch_id:, captured_at:)
          @workflow_id = workflow_id
          @batch_id = batch_id
          @captured_at = captured_at
          freeze
        end
      end

      # Groups normalized workflow membership and derived step state fields.
      class Membership
        attr_reader :dependency_job_ids_by_job_id, :job_ids, :jobs, :jobs_by_id, :step_job_ids, :step_states

        def initialize(step_job_ids:, dependency_job_ids_by_job_id:, jobs:)
          @step_job_ids = step_job_ids
          @dependency_job_ids_by_job_id = dependency_job_ids_by_job_id
          @jobs = jobs
          validate_membership
          @job_ids = jobs.map(&:id).freeze
          @jobs_by_id = jobs.to_h { |job| [job.id, job] }.freeze
          @step_states = build_step_states
          freeze
        end

        private

        def validate_membership
          snapshot_job_ids = jobs.map(&:id)
          expected_job_ids = step_job_ids.values
          return if snapshot_job_ids == expected_job_ids

          raise InvalidExecutionError, 'step_job_ids must match jobs in order'
        end

        def build_step_states
          step_job_ids.each_with_object({}) do |(step_id, job_id), states|
            states[step_id] = jobs_by_id.fetch(job_id).state
          end.freeze
        end
      end

      # Builds ordered per-step runtime inspection values.
      class StepInspection
        def initialize(identity:, membership:, child_relationships:, interaction_requirements_by_job_id:, interactions:)
          @identity = identity
          @membership = membership
          @child_relationships = child_relationships
          @interaction_requirements_by_job_id = interaction_requirements_by_job_id
          @interaction_received_at_by_job_id = InteractionDeliveries.new(
            interaction_requirements_by_job_id:,
            interactions:
          ).to_h
          @steps = build_steps
          @steps_by_id = @steps.to_h { |step_snapshot| [step_snapshot.step_id, step_snapshot] }.freeze
          freeze
        end

        attr_reader :steps

        def step(step_id)
          normalized_step_id = Workflow.send(:normalize_execution_identifier, :step_id, step_id)
          steps_by_id[normalized_step_id]
        end

        def fetch_step(step_id)
          normalized_step_id = Workflow.send(:normalize_execution_identifier, :step_id, step_id)
          steps_by_id.fetch(normalized_step_id) do
            raise InvalidExecutionError, "unknown workflow step #{normalized_step_id.inspect}"
          end
        end

        private

        attr_reader :child_relationships, :identity, :interaction_received_at_by_job_id,
                    :interaction_requirements_by_job_id, :membership, :steps_by_id

        def build_steps
          membership.step_job_ids.map do |step_id, job_id|
            prerequisite_job_ids = membership.dependency_job_ids_by_job_id.fetch(job_id, [])
            interaction_requirement = interaction_requirements_by_job_id[job_id]
            StepSnapshot.new(
              workflow_id: identity.workflow_id,
              batch_id: identity.batch_id,
              step_id:,
              job_id:,
              job: membership.jobs_by_id.fetch(job_id),
              prerequisite_job_ids:,
              prerequisite_states: prerequisite_states_for(prerequisite_job_ids),
              child_workflow_id: child_relationships.child_workflow_id(step_id),
              child_workflow: child_relationships.child_workflow(step_id),
              interaction_kind: interaction_requirement&.fetch(:kind, nil),
              interaction_name: interaction_requirement&.fetch(:name, nil),
              interaction_received_at: interaction_received_at_by_job_id[job_id]
            )
          end.freeze
        end

        def prerequisite_states_for(prerequisite_job_ids)
          prerequisite_job_ids.to_h do |job_id|
            prerequisite_job = membership.jobs_by_id[job_id]
            [job_id, prerequisite_job&.state]
          end
        end
      end

      # Normalizes child workflow declarations by parent step id.
      class ChildWorkflowIds
        def initialize(child_workflow_ids_by_step_id)
          @child_workflow_ids_by_step_id = child_workflow_ids_by_step_id
        end

        def to_h
          raise InvalidExecutionError, 'child_workflow_ids_by_step_id must be a Hash' unless child_workflow_ids_by_step_id.is_a?(Hash)

          child_workflow_ids_by_step_id.each_with_object({}) do |(step_id, child_workflow_id), normalized|
            normalized_step_id = Workflow.send(:normalize_execution_identifier, :step_id, step_id)
            normalized[normalized_step_id] = Workflow.send(:normalize_identifier, :child_workflow_id, child_workflow_id)
          end.freeze
        end

        private

        attr_reader :child_workflow_ids_by_step_id
      end

      # Normalizes child workflow relationship snapshots.
      class ChildWorkflowList
        def initialize(child_workflows)
          @child_workflows = child_workflows
        end

        def to_a
          raise InvalidExecutionError, 'child_workflows must be an Array' unless child_workflows.is_a?(Array)

          child_workflows.each do |child_workflow|
            unless child_workflow.is_a?(ChildWorkflowSnapshot)
              raise InvalidExecutionError, 'child_workflows entries must be Karya::Workflow::ChildWorkflowSnapshot'
            end
          end
          child_workflows.dup.freeze
        end

        private

        attr_reader :child_workflows
      end

      # Normalizes workflow interaction snapshots.
      class InteractionList
        def initialize(interactions)
          @interactions = interactions
        end

        def to_a
          raise InvalidExecutionError, 'interactions must be an Array' unless interactions.is_a?(Array)

          interactions.each do |interaction|
            raise InvalidExecutionError, 'interactions entries must be Karya::Workflow::InteractionSnapshot' unless interaction.is_a?(InteractionSnapshot)
          end
          interactions.dup.freeze
        end

        private

        attr_reader :interactions
      end

      # Normalizes workflow interaction requirements keyed by concrete job id.
      class InteractionRequirements
        def initialize(interaction_requirements_by_job_id)
          @interaction_requirements_by_job_id = interaction_requirements_by_job_id
        end

        def to_h
          raise InvalidExecutionError, 'interaction_requirements_by_job_id must be a Hash' unless interaction_requirements_by_job_id.is_a?(Hash)

          interaction_requirements_by_job_id.each_with_object({}) do |(job_id, requirement), normalized|
            normalized_job_id = Workflow.send(:normalize_execution_identifier, :job_id, job_id)
            raise InvalidExecutionError, "duplicate interaction requirement job #{normalized_job_id.inspect}" if normalized.key?(normalized_job_id)

            normalized[normalized_job_id] = Requirement.new(requirement).to_h
          end.freeze
        end

        private

        attr_reader :interaction_requirements_by_job_id

        # Normalizes one interaction requirement entry.
        class Requirement
          def initialize(requirement)
            @requirement = requirement
          end

          def to_h
            raise InvalidExecutionError, 'interaction requirement must be a Hash' unless requirement.is_a?(Hash)

            kind = requirement.fetch(:kind) { raise InvalidExecutionError, 'interaction requirement must include :kind' }
            name = requirement.fetch(:name) { raise InvalidExecutionError, 'interaction requirement must include :name' }
            kind = kind.to_sym
            raise InvalidExecutionError, 'interaction requirement kind must be :signal or :event' unless %i[signal event].include?(kind)

            {
              kind:,
              name: Workflow.send(:normalize_identifier, :interaction_name, name)
            }.freeze
          end

          private

          attr_reader :requirement
        end

        private_constant :Requirement
      end

      # Resolves interaction delivery timestamps for gated workflow jobs.
      class InteractionDeliveries
        def initialize(interaction_requirements_by_job_id:, interactions:)
          @interaction_requirements_by_job_id = interaction_requirements_by_job_id
          @interactions = interactions
        end

        def to_h
          delivery_index = DeliveryIndex.new(interactions).to_h
          matching_job_index = MatchingJobIndex.new(interaction_requirements_by_job_id).to_h
          ReceivedAtByJobId.new(delivery_index:, matching_job_index:).to_h
        end

        private

        attr_reader :interaction_requirements_by_job_id, :interactions

        # Builds delivery timestamps keyed by interaction identity.
        class DeliveryIndex
          def initialize(interactions)
            @interactions = interactions
          end

          def to_h
            interactions.to_h { |interaction| DeliveryEntry.new(interaction).to_pair }
          end

          private

          attr_reader :interactions

          # Converts one interaction snapshot into its identity and timestamp.
          class DeliveryEntry
            def initialize(interaction)
              @interaction = interaction
            end

            def to_pair
              [[interaction.kind, interaction.name], interaction.received_at]
            end

            private

            attr_reader :interaction
          end
        end

        # Builds workflow job ids keyed by required interaction identity.
        class MatchingJobIndex
          def initialize(interaction_requirements_by_job_id)
            @interaction_requirements_by_job_id = interaction_requirements_by_job_id
            @index = {}
          end

          def to_h
            interaction_requirements_by_job_id.each do |job_id, requirement|
              register(RequirementKey.new(requirement).to_a, job_id)
            end
            index.freeze
          end

          private

          attr_reader :index, :interaction_requirements_by_job_id

          def register(interaction_key, job_id)
            job_ids = index[interaction_key]
            if job_ids
              job_ids << job_id
            else
              index[interaction_key] = [job_id]
            end
          end

          # Converts one interaction requirement into its lookup key.
          class RequirementKey
            def initialize(requirement)
              @requirement = requirement
            end

            def to_a
              [requirement.fetch(:kind), requirement.fetch(:name)]
            end

            private

            attr_reader :requirement
          end
        end

        # Builds received-at timestamps keyed by gated workflow job id.
        class ReceivedAtByJobId
          def initialize(delivery_index:, matching_job_index:)
            @delivery_index = delivery_index
            @matching_job_index = matching_job_index
            @received_at_by_job_id = {}
          end

          def to_h
            delivery_index.each do |interaction_key, received_at|
              register(interaction_key, received_at)
            end
            received_at_by_job_id.freeze
          end

          private

          attr_reader :delivery_index, :matching_job_index, :received_at_by_job_id

          def register(interaction_key, received_at)
            matching_job_index.fetch(interaction_key, []).each do |job_id|
              received_at_by_job_id[job_id] = received_at
            end
          end
        end
      end

      # Groups snapshot state summary fields.
      class SummaryData
        attr_reader :completed_count, :failed_count, :state, :state_counts, :total_count

        def initialize(membership, step_inspection)
          jobs = membership.jobs
          summary = Summary.new(jobs)
          @state_counts = summary.state_counts
          @total_count = jobs.length
          @completed_count = summary.completed_count
          @failed_count = summary.failed_count
          @state = State.new(jobs:, steps: step_inspection.steps).to_sym
          freeze
        end
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

      # Normalizes the ordered workflow step to job mapping.
      class StepJobIds
        def initialize(step_job_ids)
          @step_job_ids = step_job_ids
        end

        def to_h
          raise InvalidExecutionError, 'step_job_ids must be a Hash' unless step_job_ids.is_a?(Hash)
          raise InvalidExecutionError, 'workflow snapshot must include at least one step' if step_job_ids.empty?

          step_job_ids.each_with_object({}) do |(step_id, job_id), normalized|
            normalized_step_id = Workflow.send(:normalize_execution_identifier, :step_id, step_id)
            raise InvalidExecutionError, "duplicate workflow step #{normalized_step_id.inspect}" if normalized.key?(normalized_step_id)

            normalized[normalized_step_id] = Workflow.send(:normalize_execution_identifier, :job_id, job_id)
          end.freeze
        end

        private

        attr_reader :step_job_ids
      end

      # Normalizes dependency metadata keyed by concrete job id.
      class DependencyJobIds
        def initialize(dependency_job_ids_by_job_id)
          @dependency_job_ids_by_job_id = dependency_job_ids_by_job_id
        end

        def to_h
          raise InvalidExecutionError, 'dependency_job_ids_by_job_id must be a Hash' unless dependency_job_ids_by_job_id.is_a?(Hash)

          dependency_job_ids_by_job_id.each_with_object({}) do |(job_id, dependency_job_ids), normalized|
            normalized_job_id = Workflow.send(:normalize_execution_identifier, :job_id, job_id)
            raise InvalidExecutionError, 'dependency job ids must be an Array' unless dependency_job_ids.is_a?(Array)
            raise InvalidExecutionError, "duplicate dependency job id #{normalized_job_id.inspect}" if normalized.key?(normalized_job_id)

            normalized[normalized_job_id] = DependencyJobIdList.new(dependency_job_ids).to_a
          end.freeze
        end

        private

        attr_reader :dependency_job_ids_by_job_id
      end

      # Normalizes one prerequisite job id list.
      class DependencyJobIdList
        def initialize(dependency_job_ids)
          @dependency_job_ids = dependency_job_ids
        end

        def to_a
          dependency_job_ids.map do |dependency_job_id|
            Workflow.send(:normalize_execution_identifier, :dependency_job_id, dependency_job_id)
          end.freeze
        end

        private

        attr_reader :dependency_job_ids
      end

      # Normalizes a snapshot job list while preserving current job objects.
      class JobList
        def initialize(jobs)
          @jobs = jobs
        end

        def to_a
          raise InvalidExecutionError, 'jobs must be an Array' unless jobs.is_a?(Array)
          raise InvalidExecutionError, 'workflow snapshot must include at least one job' if jobs.empty?

          jobs.each do |job|
            raise InvalidExecutionError, 'jobs entries must be Karya::Job' unless job.is_a?(Job)
          end
          jobs.dup.freeze
        end

        private

        attr_reader :jobs
      end

      # Summarizes current workflow job states.
      class Summary
        def initialize(jobs)
          @jobs = jobs
        end

        def state_counts
          @state_counts ||= jobs.each_with_object(Hash.new(0)) do |job, counts|
            counts[job.state] += 1
          end.freeze
        end

        def completed_count
          jobs.count { |job| COMPLETED_STATES.include?(job.state) }
        end

        def failed_count
          jobs.count { |job| FAILED_STATES.include?(job.state) }
        end

        private

        attr_reader :jobs
      end

      # Wraps a job state query used by workflow state derivation.
      class JobState
        def initialize(job)
          @job = job
        end

        def active?
          !job.terminal? && !WAITING_STATES.include?(job.state)
        end

        private

        attr_reader :job
      end

      # Derives workflow state from current job states and prerequisites.
      class State
        def initialize(jobs:, steps:)
          @jobs = jobs
          @steps = steps
        end

        def to_sym
          return :failed if failed?
          return :succeeded if only_state?(:succeeded)
          return :cancelled if only_state?(:cancelled)
          return :failed if terminal_mixed?
          return :running if running?
          return :blocked if blocked?
          return :running if progressed?

          :pending
        end

        private

        attr_reader :jobs, :steps

        def failed?
          jobs.any? { |job| FAILED_STATES.include?(job.state) }
        end

        def only_state?(state)
          jobs.all? { |job| job.state == state }
        end

        def terminal_mixed?
          jobs.all?(&:terminal?)
        end

        def running?
          jobs.any? { |job| JobState.new(job).active? }
        end

        def progressed?
          jobs.any? { |job| !WAITING_STATES.include?(job.state) }
        end

        def blocked?
          steps.any?(&:blocked?)
        end
      end

      private_constant :Attributes,
                       :ChildRelationships,
                       :ChildWorkflowIds,
                       :ChildWorkflowList,
                       :COMPLETED_STATES,
                       :DependencyJobIdList,
                       :DependencyJobIds,
                       :FAILED_STATES,
                       :Identity,
                       :InteractionDeliveries,
                       :InteractionList,
                       :InteractionRequirements,
                       :JobState,
                       :JobList,
                       :Membership,
                       :OPTIONAL_ATTRIBUTES,
                       :REQUIRED_ATTRIBUTES,
                       :State,
                       :StepInspection,
                       :StepJobIds,
                       :SUPPORTED_ATTRIBUTES,
                       :Summary,
                       :SummaryData,
                       :Timestamp,
                       :WAITING_STATES

      private

      attr_reader :child_relationships, :identity, :membership, :step_inspection, :summary_data
    end
  end
end
