# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'base'
require_relative 'job_lifecycle'
require_relative 'job/attributes'
require_relative 'job/immutable_arguments'

module Karya
  # Raised when a canonical job attribute is invalid.
  class InvalidJobAttributeError < Error; end

  # Immutable value object for the canonical queued job model.
  class Job
    attr_reader :arguments, :attempt, :created_at, :handler, :id, :queue, :state, :updated_at

    def initialize(**attributes)
      normalized_attributes = Attributes.new(attributes).to_h

      @id = normalized_attributes.fetch(:id)
      @queue = normalized_attributes.fetch(:queue)
      @handler = normalized_attributes.fetch(:handler)
      @arguments = normalized_attributes.fetch(:arguments)
      @state = normalized_attributes.fetch(:state)
      @attempt = normalized_attributes.fetch(:attempt)
      @created_at = normalized_attributes.fetch(:created_at)
      @lifecycle = normalized_attributes.fetch(:lifecycle)
      @updated_at = normalized_attributes.fetch(:updated_at)

      freeze
    end

    def can_transition_to?(next_state)
      lifecycle.valid_transition?(from: state, to: next_state)
    rescue JobLifecycle::InvalidJobStateError
      false
    end

    def transition_to(next_state, updated_at:, attempt: self.attempt)
      normalized_next_state = lifecycle.validate_transition!(from: state, to: next_state)

      self.class.new(
        id:,
        queue:,
        handler:,
        arguments:,
        lifecycle:,
        state: normalized_next_state,
        attempt:,
        created_at:,
        updated_at:
      )
    end

    def terminal?
      lifecycle.terminal?(state)
    end

    private_constant :Attributes, :ImmutableArguments

    private

    attr_reader :lifecycle
  end
end
