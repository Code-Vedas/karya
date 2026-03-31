# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'base'
require_relative 'job_lifecycle/errors'
require_relative 'job_lifecycle/constants'
require_relative 'job_lifecycle/normalization'
require_relative 'job_lifecycle/state_manager'
require_relative 'job_lifecycle/extension'
require_relative 'job_lifecycle/registry'

module Karya
  # Canonical lifecycle rules for queued job instances.
  module JobLifecycle
    module_function

    # Re-export constants for backward compatibility
    SUBMISSION = Constants::SUBMISSION
    QUEUED = Constants::QUEUED
    RESERVED = Constants::RESERVED
    RUNNING = Constants::RUNNING
    SUCCEEDED = Constants::SUCCEEDED
    FAILED = Constants::FAILED
    RETRY_PENDING = Constants::RETRY_PENDING
    CANCELLED = Constants::CANCELLED
    STATES = Constants::STATES
    TRANSITIONS = Constants::TRANSITIONS
    TERMINAL_STATES = Constants::TERMINAL_STATES

    private_constant :Constants

    @default_registry = Registry.new

    class << self
      def default_registry
        @default_registry ||= Registry.new
      end

      def instance_variable_get(name)
        state_manager = default_registry.state_manager
        case name
        when :@extension_state_names
          state_manager.extension_state_names
        when :@extension_terminal_state_names
          state_manager.extension_terminal_state_names
        when :@extension_transitions
          state_manager.extension_transitions
        when :@mutex
          state_manager.mutex
        else
          super
        end
      end
    end

    def normalize_state(state)
      default_registry.normalize_state(state)
    end

    def validate_state!(state)
      default_registry.validate_state!(state)
    end

    def valid_transition?(from:, to:)
      default_registry.valid_transition?(from:, to:)
    end

    def validate_transition!(from:, to:)
      default_registry.validate_transition!(from:, to:)
    end

    def terminal?(state)
      default_registry.terminal?(state)
    end

    def register_state(state, terminal: false)
      default_registry.register_state(state, terminal:)
    end

    def register_transition(from:, to:)
      default_registry.register_transition(from:, to:)
    end

    def states
      default_registry.states
    end

    def transitions
      default_registry.transitions
    end

    def terminal_states
      default_registry.terminal_states
    end

    def clear_extensions!
      default_registry.clear_extensions!
    end
    module_function :clear_extensions!
    private_class_method :clear_extensions!

    private

    def normalize_state_locked(state)
      default_registry.state_manager.normalize_state_locked(state)
    end
    module_function :normalize_state_locked
    private_class_method :normalize_state_locked

    def state_names_locked
      default_registry.state_manager.state_names_locked
    end
    module_function :state_names_locked
    private_class_method :state_names_locked

    def transition_names_locked
      default_registry.state_manager.transition_names_locked
    end
    module_function :transition_names_locked
    private_class_method :transition_names_locked

    def terminal_state_names_locked
      default_registry.state_manager.terminal_state_names_locked
    end
    module_function :terminal_state_names_locked
    private_class_method :terminal_state_names_locked

    def invalidate_caches
      default_registry.state_manager.invalidate_caches
    end
    module_function :invalidate_caches
    private_class_method :invalidate_caches

    def normalize_state_name(state)
      Normalization.normalize_state_name(state)
    end
    module_function :normalize_state_name
    private_class_method :normalize_state_name

    def validate_state_locked!(state_name)
      default_registry.state_manager.validate_state_locked!(state_name)
    end
    module_function :validate_state_locked!
    private_class_method :validate_state_locked!

    def extension_state_name?(state_name)
      default_registry.state_manager.extension_state_name?(state_name)
    end
    module_function :extension_state_name?
    private_class_method :extension_state_name?

    def public_state(state_name)
      default_registry.state_manager.public_state(state_name)
    end
    module_function :public_state
    private_class_method :public_state

    def transition_values(next_state_names)
      default_registry.state_manager.transition_values(next_state_names)
    end
    module_function :transition_values
    private_class_method :transition_values

    def lowercase_letter?(character)
      Normalization.lowercase_letter?(character)
    end
    module_function :lowercase_letter?
    private_class_method :lowercase_letter?

    def digit?(character)
      Normalization.digit?(character)
    end
    module_function :digit?
    private_class_method :digit?

    def raise_blank_state_error!
      Normalization.raise_blank_state_error!
    end
    module_function :raise_blank_state_error!
    private_class_method :raise_blank_state_error!
  end
end
