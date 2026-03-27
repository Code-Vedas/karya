# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

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
      @updated_at = normalized_attributes.fetch(:updated_at)

      freeze
    end

    def can_transition_to?(next_state)
      JobLifecycle.valid_transition?(from: state, to: next_state)
    end

    def transition_to(next_state, updated_at:)
      normalized_next_state = JobLifecycle.validate_transition!(from: state, to: next_state)

      self.class.new(
        id:,
        queue:,
        handler:,
        arguments:,
        state: normalized_next_state,
        attempt:,
        created_at:,
        updated_at:
      )
    end

    def terminal?
      JobLifecycle.terminal?(state)
    end

    # Normalizes constructor input without leaking validation helpers onto the public job API.
    class Attributes
      def initialize(attributes)
        @attributes = attributes
      end

      def to_h
        created_at = normalize_timestamp(:created_at, required(:created_at))
        attempt = optional(:attempt, 0)
        raise InvalidJobAttributeError, 'attempt must be a non-negative Integer' unless attempt.is_a?(Integer) && attempt >= 0

        {
          id: normalize_identifier(:id, required(:id)),
          queue: normalize_identifier(:queue, required(:queue)),
          handler: normalize_identifier(:handler, required(:handler)),
          arguments: ImmutableArguments.new(optional(:arguments, {})).normalize,
          state: JobLifecycle.normalize_state(required(:state)),
          attempt:,
          created_at:,
          updated_at: normalize_timestamp(:updated_at, optional(:updated_at, created_at))
        }
      end

      private

      attr_reader :attributes

      def required(name)
        attributes.fetch(name)
      rescue KeyError
        raise InvalidJobAttributeError, "#{name} must be present"
      end

      def optional(name, default)
        attributes.fetch(name, default)
      end

      def normalize_identifier(name, value)
        normalized_value = value.to_s.strip
        return normalized_value unless normalized_value.empty?

        raise InvalidJobAttributeError, "#{name} must be present"
      end

      def normalize_timestamp(name, value)
        return value if value.is_a?(Time)

        raise InvalidJobAttributeError, "#{name} must be a Time"
      end
    end

    # Normalizes and deeply freezes job arguments so job instances remain immutable.
    class ImmutableArguments
      def initialize(arguments)
        @arguments = arguments
      end

      def normalize
        raise InvalidJobAttributeError, 'arguments must be a Hash' unless arguments.is_a?(Hash)

        freeze_hash(arguments)
      end

      private

      attr_reader :arguments

      def freeze_hash(value)
        value.each_with_object({}) do |(key, item), normalized|
          normalized_key = key.to_s.strip
          raise InvalidJobAttributeError, 'argument keys must be present' if normalized_key.empty?

          normalized[normalized_key.to_sym] = freeze_value(item)
        end.freeze
      end

      def freeze_value(value)
        case value
        when Hash
          freeze_hash(value)
        when Array
          value.map { |item| freeze_value(item) }.freeze
        else
          value.freeze
        end
      end
    end

    private_constant :Attributes, :ImmutableArguments
  end
end
