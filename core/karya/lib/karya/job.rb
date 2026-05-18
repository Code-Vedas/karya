# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'base'
require_relative 'job_lifecycle'
require_relative 'job/attributes'
require_relative 'job/immutable_arguments'
require_relative 'retry_policy'

module Karya
  # Raised when a canonical job attribute is invalid.
  class InvalidJobAttributeError < Error; end

  # Immutable value object for the canonical queued job model.
  class Job
    # Serializes jobs without persisting the runtime lifecycle registry object.
    module MarshalSupport
      # Captures custom lifecycle extensions so marshaled jobs can restore them safely.
      class LifecycleExtensionsSnapshot
        def initialize(state_names:, terminal_state_names:, transitions:)
          @state_names = state_names
          @terminal_state_names = terminal_state_names
          @transitions = transitions
        end

        def self.dump(lifecycle)
          raise TypeError, 'Karya::Job marshal_dump only supports JobLifecycle::Registry lifecycles' unless lifecycle.is_a?(Karya::JobLifecycle::Registry)

          new(
            state_names: lifecycle.send(:extension_state_names),
            terminal_state_names: lifecycle.send(:extension_terminal_state_names),
            transitions: lifecycle.send(:extension_transitions)
          ).to_h
        end

        def self.load(snapshot)
          new(
            state_names: snapshot.fetch(:state_names),
            terminal_state_names: snapshot.fetch(:terminal_state_names),
            transitions: snapshot.fetch(:transitions)
          ).restore
        end

        def to_h
          {
            state_names:,
            terminal_state_names:,
            transitions:
          }
        end

        def restore
          Karya::JobLifecycle::Registry.new.tap do |registry|
            register_states(registry)
            register_transitions(registry)
          end
        end

        private

        attr_reader :state_names, :terminal_state_names, :transitions

        def register_states(registry)
          state_names.each do |state_name|
            registry.register_state(state_name, terminal: terminal_state_names.include?(state_name))
          end
        end

        def register_transitions(registry)
          transitions.each_key do |from_state|
            register_transition_targets(registry, from_state)
          end
        end

        def register_transition_targets(registry, from_state)
          transitions.fetch(from_state).each do |to_state|
            registry.register_transition(from: from_state, to: to_state)
          end
        end
      end
      private_constant :LifecycleExtensionsSnapshot

      def marshal_dump
        {
          id:,
          queue:,
          handler:,
          arguments:,
          priority:,
          concurrency_scope:,
          rate_limit_scope:,
          retry_policy:,
          execution_timeout:,
          expires_at:,
          idempotency_key:,
          uniqueness_key:,
          uniqueness_scope:,
          lifecycle_extensions: lifecycle_extensions_snapshot,
          state:,
          attempt:,
          created_at:,
          updated_at:,
          next_retry_at:,
          failure_classification:,
          dead_letter_reason:,
          dead_lettered_at:,
          dead_letter_source_state:
        }
      end

      def marshal_load(attributes)
        reloaded_job = self.class.new(
          **attributes,
          lifecycle: LifecycleExtensionsSnapshot.load(attributes.fetch(:lifecycle_extensions))
        )

        @identity = reloaded_job.send(:identity)
        @scheduling = reloaded_job.send(:scheduling)
        @lifecycle_state = reloaded_job.send(:lifecycle_state)
        freeze
      end

      private

      def lifecycle_extensions_snapshot
        LifecycleExtensionsSnapshot.dump(lifecycle)
      end
    end
    private_constant :MarshalSupport
    include MarshalSupport

    private :marshal_dump, :marshal_load

    # Canonical immutable routing payload for one job instance.
    Identity = Struct.new(:id, :queue, :handler, :arguments)
    # Canonical immutable scheduling metadata for job selection policies.
    Scheduling = Struct.new(
      :priority,
      :concurrency_scope,
      :rate_limit_scope,
      :retry_policy,
      :execution_timeout,
      :expires_at,
      :idempotency_key,
      :uniqueness_key,
      :uniqueness_scope
    )
    # Canonical immutable lifecycle state for one job instance.
    LifecycleState = Struct.new(
      :state,
      :attempt,
      :created_at,
      :updated_at,
      :next_retry_at,
      :failure_classification,
      :dead_letter_reason,
      :dead_lettered_at,
      :dead_letter_source_state,
      :lifecycle
    )
    # Normalizes optional transition-only overrides without growing the job API surface.
    class TransitionOverrides
      ALLOWED_KEYS = %i[
        dead_letter_reason
        dead_lettered_at
        dead_letter_source_state
        execution_timeout
        expires_at
      ].freeze

      def initialize(job, overrides)
        @job = job
        @overrides = overrides
      end

      def to_h
        unexpected_keys = overrides.keys - ALLOWED_KEYS
        raise ArgumentError, "unknown keywords: #{unexpected_keys.join(', ')}" unless unexpected_keys.empty?

        {
          dead_letter_reason: overrides.fetch(:dead_letter_reason, job.dead_letter_reason),
          dead_lettered_at: overrides.fetch(:dead_lettered_at, job.dead_lettered_at),
          dead_letter_source_state: overrides.fetch(:dead_letter_source_state, job.dead_letter_source_state),
          execution_timeout: overrides.fetch(:execution_timeout, job.execution_timeout),
          expires_at: overrides.fetch(:expires_at, job.expires_at)
        }
      end

      private

      attr_reader :job, :overrides
    end

    # Groups normalized constructor fields into lifecycle-safe components.
    class Components
      def initialize(attributes)
        @attributes = attributes
      end

      def identity
        Identity.new(
          attributes.fetch(:id),
          attributes.fetch(:queue),
          attributes.fetch(:handler),
          attributes.fetch(:arguments)
        ).freeze
      end

      def scheduling
        Scheduling.new(
          attributes.fetch(:priority),
          attributes.fetch(:concurrency_scope),
          attributes.fetch(:rate_limit_scope),
          attributes.fetch(:retry_policy),
          attributes.fetch(:execution_timeout),
          attributes.fetch(:expires_at),
          attributes.fetch(:idempotency_key),
          attributes.fetch(:uniqueness_key),
          attributes.fetch(:uniqueness_scope)
        ).freeze
      end

      def lifecycle_state
        LifecycleState.new(
          attributes.fetch(:state),
          attributes.fetch(:attempt),
          attributes.fetch(:created_at),
          attributes.fetch(:updated_at),
          attributes.fetch(:next_retry_at),
          attributes.fetch(:failure_classification),
          attributes.fetch(:dead_letter_reason),
          attributes.fetch(:dead_lettered_at),
          attributes.fetch(:dead_letter_source_state),
          attributes.fetch(:lifecycle)
        ).freeze
      end

      private

      attr_reader :attributes
    end

    def initialize(**attributes)
      components = Components.new(Attributes.new(attributes).to_h)

      @identity = components.identity
      @scheduling = components.scheduling
      @lifecycle_state = components.lifecycle_state

      freeze
    end

    def can_transition_to?(next_state)
      lifecycle.valid_transition?(from: state, to: next_state)
    rescue JobLifecycle::InvalidJobStateError
      false
    end

    def transition_to(
      next_state,
      updated_at:,
      attempt: self.attempt,
      retry_policy: self.retry_policy,
      next_retry_at: self.next_retry_at,
      failure_classification: self.failure_classification,
      **overrides
    )
      transition_overrides = TransitionOverrides.new(self, overrides).to_h
      normalized_next_state = lifecycle.validate_transition!(from: state, to: next_state)

      self.class.new(
        id:,
        queue:,
        handler:,
        arguments:,
        priority:,
        concurrency_scope:,
        rate_limit_scope:,
        retry_policy:,
        execution_timeout: transition_overrides.fetch(:execution_timeout),
        expires_at: transition_overrides.fetch(:expires_at),
        idempotency_key: idempotency_key,
        uniqueness_key: uniqueness_key,
        uniqueness_scope: uniqueness_scope,
        lifecycle:,
        state: normalized_next_state,
        attempt:,
        created_at:,
        updated_at:,
        next_retry_at:,
        failure_classification:,
        dead_letter_reason: transition_overrides.fetch(:dead_letter_reason),
        dead_lettered_at: transition_overrides.fetch(:dead_lettered_at),
        dead_letter_source_state: transition_overrides.fetch(:dead_letter_source_state)
      )
    end

    def expire(updated_at:)
      self.class.new(
        id:,
        queue:,
        handler:,
        arguments:,
        priority:,
        concurrency_scope:,
        rate_limit_scope:,
        retry_policy:,
        execution_timeout:,
        expires_at:,
        idempotency_key:,
        uniqueness_key:,
        uniqueness_scope:,
        lifecycle:,
        state: :failed,
        attempt:,
        created_at:,
        updated_at:,
        next_retry_at: nil,
        failure_classification: :expired,
        dead_letter_reason: nil,
        dead_lettered_at: nil,
        dead_letter_source_state: nil
      )
    end

    def terminal?
      lifecycle.terminal?(state)
    end

    def id = identity.id
    def queue = identity.queue
    def handler = identity.handler
    def arguments = identity.arguments
    def priority = scheduling.priority
    def concurrency_scope = scheduling.concurrency_scope
    def rate_limit_scope = scheduling.rate_limit_scope
    def concurrency_key = concurrency_scope&.key
    def rate_limit_key = rate_limit_scope&.key
    def retry_policy = scheduling.retry_policy
    def execution_timeout = scheduling.execution_timeout
    def expires_at = scheduling.expires_at
    def idempotency_key = scheduling.idempotency_key
    def uniqueness_key = scheduling.uniqueness_key
    def uniqueness_scope = scheduling.uniqueness_scope
    def state = lifecycle_state.state
    def attempt = lifecycle_state.attempt
    def created_at = lifecycle_state.created_at
    def updated_at = lifecycle_state.updated_at
    def next_retry_at = lifecycle_state.next_retry_at
    def failure_classification = lifecycle_state.failure_classification
    def dead_letter_reason = lifecycle_state.dead_letter_reason
    def dead_lettered_at = lifecycle_state.dead_lettered_at
    def dead_letter_source_state = lifecycle_state.dead_letter_source_state

    private_constant :Attributes, :Components, :ImmutableArguments, :TransitionOverrides

    private

    attr_reader :identity, :lifecycle_state, :scheduling

    def lifecycle
      lifecycle_state.lifecycle
    end
  end
end
