# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'

module Karya
  module Internal
    # Shared framework-native workflow DSL and queue-store facade.
    module FrameworkWorkflow
      # Normalizes framework workflow DSL values into core runtime shapes.
      module Normalization
        module_function

        def step_id(value)
          Karya::Workflow.send(:normalize_identifier, :step_id, value)
        end

        def payload(value)
          return value.to_payload if value.respond_to?(:to_payload)

          value
        end

        def now(value)
          value.is_a?(Time) ? value.utc : Time.at(value.to_f).utc
        end

        def job_class(value)
          return value if value.is_a?(Class) && value < Karya::FrameworkJob::Base

          raise ArgumentError, 'workflow steps must declare job: with a Karya framework job class'
        end
      end

      # Binds one framework workflow step to its executable job classes and payloads.
      class StepBinding
        attr_reader :arguments, :compensation_arguments, :compensation_job_class, :id,
                    :job_class, :options, :step_id

        def initialize(id:, job_class:, arguments:, compensation_job_class:, compensation_arguments:, **options)
          @id = id
          @step_id = Normalization.step_id(id)
          @job_class = Normalization.job_class(job_class)
          @arguments = Normalization.payload(arguments)
          @compensation_job_class = compensation_job_class ? Normalization.job_class(compensation_job_class) : nil
          @compensation_arguments = Normalization.payload(compensation_arguments)
          @options = options.freeze
        end

        def to_core_definition(builder)
          builder.step(
            id,
            handler: job_class.handler_name,
            arguments:,
            depends_on: options.fetch(:depends_on),
            compensate_with: compensation_job_class&.handler_name,
            compensation_arguments:,
            child_workflow: options.fetch(:child_workflow),
            wait_for_approval: options.fetch(:wait_for_approval),
            wait_for_signal: options.fetch(:wait_for_signal),
            wait_for_event: options.fetch(:wait_for_event)
          )
        end
      end

      # Resolves framework workflow step bindings into executable queued jobs.
      class StepRegistry
        EMPTY_PAYLOAD = Karya::FrameworkJob::ArgumentCodec.dump([], {}).freeze

        def initialize(bindings)
          @bindings = bindings.freeze
        end

        attr_reader :bindings

        def job_classes
          bindings.to_h { |binding| [binding.step_id, binding.job_class] }
        end

        def default_arguments
          bindings.to_h { |binding| [binding.step_id, binding.arguments] }
        end

        def compensation_job_classes
          bindings.filter_map do |binding|
            [binding.step_id, binding.compensation_job_class] if binding.compensation_job_class
          end.to_h
        end

        def compensation_arguments
          bindings.to_h { |binding| [binding.step_id, binding.compensation_arguments] }
        end

        def materialize_jobs(step_arguments:, now:, compensation: false)
          classes = compensation ? compensation_job_classes : job_classes
          defaults = compensation ? compensation_arguments : default_arguments

          classes.each_with_object({}) do |(step_id, job_class), jobs|
            jobs[step_id] = job_class.build_job(
              arguments_payload: resolved_payload(step_arguments, step_id, defaults),
              now:,
              job_id: SecureRandom.uuid
            )
          end
        end

        private

        def resolved_payload(step_arguments, step_id, defaults)
          symbol_step_id = step_id.to_sym
          return Normalization.payload(step_arguments.fetch(step_id)) if step_arguments.key?(step_id)
          return Normalization.payload(step_arguments.fetch(symbol_step_id)) if step_arguments.key?(symbol_step_id)

          defaults.fetch(step_id, EMPTY_PAYLOAD)
        end
      end

      # Delegates framework workflow runtime calls into the configured queue store.
      class QueueStoreFacade
        def initialize(queue_store: Karya.queue_store)
          @queue_store = queue_store
        end

        attr_reader :queue_store

        def enqueue_workflow(**)
          queue_store.enqueue_workflow(**)
        end

        def batch_snapshot(**)
          queue_store.batch_snapshot(**)
        end

        def workflow_snapshot(**)
          queue_store.workflow_snapshot(**)
        end

        def workflow_history(**)
          queue_store.workflow_history(**)
        end

        def query_workflow(**)
          queue_store.query_workflow(**)
        end

        def deliver_workflow_signal(**)
          queue_store.deliver_workflow_signal(**)
        end

        def deliver_workflow_event(**)
          queue_store.deliver_workflow_event(**)
        end

        def pause_workflow(**)
          queue_store.pause_workflow(**)
        end

        def resume_workflow(**)
          queue_store.resume_workflow(**)
        end

        def approve_workflow_checkpoints(**)
          queue_store.approve_workflow_checkpoints(**)
        end

        def reject_workflow_checkpoints(**)
          queue_store.reject_workflow_checkpoints(**)
        end

        def retry_workflow_steps(**)
          queue_store.retry_workflow_steps(**)
        end

        def dead_letter_workflow_steps(**)
          queue_store.dead_letter_workflow_steps(**)
        end

        def replay_workflow_steps(**)
          queue_store.replay_workflow_steps(**)
        end

        def retry_dead_letter_workflow_steps(**)
          queue_store.retry_dead_letter_workflow_steps(**)
        end

        def discard_workflow_steps(**)
          queue_store.discard_workflow_steps(**)
        end

        def rollback_workflow(**)
          queue_store.rollback_workflow(**)
        end

        def enqueue_child_workflow(**)
          queue_store.enqueue_child_workflow(**)
        end

        def sync_child_workflows(**)
          queue_store.sync_child_workflows(**)
        end
      end

      # Framework workflow definition wrapper that retains job-class bindings.
      class Definition
        attr_reader :compensation_arguments_by_step_id, :compensation_job_classes_by_step_id,
                    :core_definition, :job_classes_by_step_id, :step_arguments_by_step_id

        def initialize(
          core_definition:,
          job_classes_by_step_id:,
          step_arguments_by_step_id:,
          compensation_job_classes_by_step_id:,
          compensation_arguments_by_step_id:
        )
          @core_definition = core_definition
          @job_classes_by_step_id = job_classes_by_step_id.freeze
          @step_arguments_by_step_id = step_arguments_by_step_id.freeze
          @compensation_job_classes_by_step_id = compensation_job_classes_by_step_id.freeze
          @compensation_arguments_by_step_id = compensation_arguments_by_step_id.freeze
        end

        def id = core_definition.id
        def workflow_family = core_definition.workflow_family
        def workflow_version = core_definition.workflow_version
        def default_version? = core_definition.default_version?
        def steps = core_definition.steps
      end

      # Immutable registry of framework workflow definitions.
      class Catalog
        def initialize(definitions:)
          @definitions = definitions.to_h { |definition| [definition.id, definition] }.freeze
          @core_catalog = Karya::Workflow.catalog(definitions: definitions.map(&:core_definition))
          @family_index = build_family_index(definitions)
          @default_family_index = build_default_family_index(definitions)
        end

        attr_reader :core_catalog, :definitions

        def fetch(workflow_id)
          definitions.fetch(Karya::Workflow.send(:normalize_identifier, :workflow_id, workflow_id))
        rescue KeyError => e
          raise Karya::Workflow::InvalidDefinitionError, "workflow #{workflow_id.inspect} is not registered", cause: e
        end

        def fetch_version(workflow_family:, workflow_version:)
          family = Karya::Workflow.send(:normalize_identifier, :workflow_family, workflow_family)
          version = Karya::Workflow.send(:normalize_identifier, :workflow_version, workflow_version)
          @family_index.fetch(family).fetch(version)
        rescue KeyError => e
          raise Karya::Workflow::InvalidDefinitionError,
                "workflow family #{family.inspect} does not include version #{version.inspect}",
                cause: e
        end

        def resolve(workflow_family:)
          family = Karya::Workflow.send(:normalize_identifier, :workflow_family, workflow_family)
          @default_family_index.fetch(family)
        rescue KeyError => e
          raise Karya::Workflow::InvalidDefinitionError, "workflow family #{family.inspect} has no default version", cause: e
        end

        private

        def build_family_index(definitions)
          definitions.group_by(&:workflow_family).to_h do |workflow_family, family_definitions|
            [workflow_family, versions_for_family(workflow_family, family_definitions)]
          end.freeze
        end

        def build_default_family_index(definitions)
          definitions.each_with_object({}) do |definition, defaults|
            next unless definition.default_version?

            workflow_family = definition.workflow_family
            if defaults.key?(workflow_family)
              raise Karya::Workflow::InvalidDefinitionError,
                    "workflow family #{workflow_family.inspect} declares multiple default versions"
            end

            defaults[workflow_family] = definition
          end.freeze
        end

        def versions_for_family(workflow_family, definitions)
          definitions.each_with_object({}) do |definition, versions|
            workflow_version = definition.workflow_version
            if versions.key?(workflow_version)
              raise Karya::Workflow::InvalidDefinitionError,
                    "duplicate workflow version #{workflow_version.inspect} for family #{workflow_family.inspect}"
            end

            versions[workflow_version] = definition
          end.freeze
        end
      end

      # Module mixin used by workflow source modules.
      module Source
        def workflow(id, workflow_family: nil, workflow_version: nil, default_version: true, &block)
          karya_workflow_definitions << DefinitionBuilder.new(
            id,
            workflow_family:,
            workflow_version:,
            default_version:
          ).tap { |builder| builder.instance_eval(&block) if block }.to_definition
        end

        def karya_workflow_definitions
          @karya_workflow_definitions ||= []
        end
      end

      # Framework workflow DSL builder.
      class DefinitionBuilder
        def initialize(id, workflow_family:, workflow_version:, default_version:)
          @id = id
          @workflow_family = workflow_family
          @workflow_version = workflow_version
          @default_version = default_version
          @steps = []
        end

        def step(
          id,
          job:,
          arguments: {},
          depends_on: nil,
          compensate_with: nil,
          compensation_arguments: {},
          child_workflow: nil,
          wait_for_approval: nil,
          wait_for_signal: nil,
          wait_for_event: nil
        )
          steps << StepBinding.new(
            id:,
            job_class: job,
            arguments:,
            depends_on:,
            compensation_job_class: compensate_with,
            compensation_arguments:,
            child_workflow:,
            wait_for_approval:,
            wait_for_signal:,
            wait_for_event:
          )
        end

        def to_definition
          step_bindings = steps
          core_definition = Karya::Workflow.define(
            id,
            workflow_family:,
            workflow_version:,
            default_version:
          ) do
            step_bindings.each { |binding| binding.to_core_definition(self) }
          end
          step_registry = StepRegistry.new(step_bindings)

          Definition.new(
            core_definition:,
            job_classes_by_step_id: step_registry.job_classes,
            step_arguments_by_step_id: step_registry.default_arguments,
            compensation_job_classes_by_step_id: step_registry.compensation_job_classes,
            compensation_arguments_by_step_id: step_registry.compensation_arguments
          )
        end

        private

        attr_reader :default_version, :id, :steps, :workflow_family, :workflow_version
      end

      # Shared workflow facade bound to one framework configuration.
      class Facade
        def initialize(configuration_provider:, queue_store: QueueStoreFacade.new)
          @configuration_provider = configuration_provider
          @queue_store = queue_store
        end

        def define(...)
          DefinitionBuilder.new(...).tap do |builder|
            yield builder if block_given?
          end.to_definition
        end

        def catalog
          Catalog.new(definitions: configured_definitions)
        end

        def start(definition:, batch_id:, step_arguments:, now: Time.now.utc, compensation_step_arguments: {})
          resolved_definition = resolve_definition(definition)
          queue_store.enqueue_workflow(
            definition: resolved_definition.core_definition,
            jobs_by_step_id: materialize_jobs(resolved_definition, step_arguments:, now:),
            batch_id:,
            now: Normalization.now(now),
            compensation_jobs_by_step_id: materialize_jobs(
              resolved_definition,
              step_arguments: compensation_step_arguments,
              now:,
              compensation: true
            )
          )
        end

        def batch(batch_id:, now: Time.now.utc)
          queue_store.batch_snapshot(batch_id:, now: Normalization.now(now))
        end

        def snapshot(batch_id:, now: Time.now.utc)
          queue_store.workflow_snapshot(batch_id:, now: Normalization.now(now))
        end

        def history(batch_id:, now: Time.now.utc)
          queue_store.workflow_history(batch_id:, now: Normalization.now(now))
        end

        def query(batch_id:, query:, now: Time.now.utc)
          queue_store.query_workflow(batch_id:, query:, now: Normalization.now(now))
        end

        def signal(batch_id:, signal:, payload:, now: Time.now.utc)
          queue_store.deliver_workflow_signal(batch_id:, signal:, payload:, now: Normalization.now(now))
        end

        def event(batch_id:, event:, payload:, now: Time.now.utc)
          queue_store.deliver_workflow_event(batch_id:, event:, payload:, now: Normalization.now(now))
        end

        def pause(batch_id:, now: Time.now.utc)
          queue_store.pause_workflow(batch_id:, now: Normalization.now(now))
        end

        def resume(batch_id:, now: Time.now.utc)
          queue_store.resume_workflow(batch_id:, now: Normalization.now(now))
        end

        def approve(batch_id:, step_ids:, now: Time.now.utc)
          queue_store.approve_workflow_checkpoints(batch_id:, step_ids:, now: Normalization.now(now))
        end

        def reject(batch_id:, step_ids:, reason:, now: Time.now.utc)
          queue_store.reject_workflow_checkpoints(batch_id:, step_ids:, now: Normalization.now(now), reason:)
        end

        def retry_steps(batch_id:, step_ids:, now: Time.now.utc)
          queue_store.retry_workflow_steps(batch_id:, step_ids:, now: Normalization.now(now))
        end

        def dead_letter_steps(batch_id:, step_ids:, reason:, now: Time.now.utc)
          queue_store.dead_letter_workflow_steps(batch_id:, step_ids:, now: Normalization.now(now), reason:)
        end

        def replay_steps(batch_id:, step_ids:, now: Time.now.utc)
          queue_store.replay_workflow_steps(batch_id:, step_ids:, now: Normalization.now(now))
        end

        def retry_dead_letter_steps(batch_id:, step_ids:, next_retry_at:, now: Time.now.utc)
          queue_store.retry_dead_letter_workflow_steps(
            batch_id:,
            step_ids:,
            now: Normalization.now(now),
            next_retry_at:
          )
        end

        def discard_steps(batch_id:, step_ids:, now: Time.now.utc)
          queue_store.discard_workflow_steps(batch_id:, step_ids:, now: Normalization.now(now))
        end

        def rollback(batch_id:, reason:, now: Time.now.utc)
          queue_store.rollback_workflow(batch_id:, now: Normalization.now(now), reason:)
        end

        def enqueue_child(parent_batch_id:, parent_step_id:, definition:, batch_id:, step_arguments:, now: Time.now.utc, compensation_step_arguments: {})
          resolved_definition = resolve_definition(definition)
          queue_store.enqueue_child_workflow(
            parent_batch_id:,
            parent_step_id:,
            definition: resolved_definition.core_definition,
            jobs_by_step_id: materialize_jobs(resolved_definition, step_arguments:, now:),
            batch_id:,
            now: Normalization.now(now),
            compensation_jobs_by_step_id: materialize_jobs(
              resolved_definition,
              step_arguments: compensation_step_arguments,
              now:,
              compensation: true
            )
          )
        end

        def sync_children(parent_batch_id:, now: Time.now.utc)
          queue_store.sync_child_workflows(parent_batch_id:, now: Normalization.now(now))
        end

        private

        attr_reader :configuration_provider, :queue_store

        def configured_definitions
          configuration_provider.call.workflow_sources.flat_map(&:karya_workflow_definitions)
        end

        def resolve_definition(definition)
          return definition if definition.is_a?(Definition)
          return catalog.fetch(definition) if definition.is_a?(String) || definition.is_a?(Symbol)

          raise ArgumentError, 'definition must be a framework workflow definition or registered workflow id'
        end

        def materialize_jobs(definition, step_arguments:, now:, compensation: false)
          StepRegistry.new(step_bindings_for(definition)).materialize_jobs(
            step_arguments:,
            now:,
            compensation:
          )
        end

        def step_bindings_for(definition)
          definition.steps.map do |step|
            StepBinding.new(
              id: step.id,
              job_class: definition.job_classes_by_step_id.fetch(step.id),
              arguments: definition.step_arguments_by_step_id.fetch(step.id),
              compensation_job_class: definition.compensation_job_classes_by_step_id[step.id],
              compensation_arguments: definition.compensation_arguments_by_step_id.fetch(step.id),
              depends_on: step.depends_on,
              child_workflow: step.child_workflow,
              wait_for_approval: step.wait_for_approval,
              wait_for_signal: step.wait_for_signal,
              wait_for_event: step.wait_for_event
            )
          end
        end
      end
    end
  end
end
