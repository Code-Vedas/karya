# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'base'
require_relative 'job_lifecycle'

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
    rescue InvalidJobStateError
      false
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
        created_at = TimestampNormalizer.new(:created_at, required(:created_at)).normalize
        attempt = optional(:attempt, 0)
        raise InvalidJobAttributeError, 'attempt must be a non-negative Integer' unless attempt.is_a?(Integer) && attempt >= 0

        {
          id: IdentifierNormalizer.new(:id, required(:id)).normalize,
          queue: IdentifierNormalizer.new(:queue, required(:queue)).normalize,
          handler: IdentifierNormalizer.new(:handler, required(:handler)).normalize,
          arguments: ImmutableArguments.new(optional(:arguments, {})).normalize,
          state: JobLifecycle.normalize_state(required(:state)),
          attempt:,
          created_at:,
          updated_at: TimestampNormalizer.new(:updated_at, optional(:updated_at, created_at)).normalize
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

      # Normalizes required identifier-like fields into frozen, non-blank strings.
      class IdentifierNormalizer
        def initialize(name, value)
          @name = name
          @value = value
        end

        def normalize
          normalized_value = value.to_s.strip
          return normalized_value.freeze unless normalized_value.empty?

          raise InvalidJobAttributeError, "#{name} must be present"
        end

        private

        attr_reader :name, :value
      end

      # Normalizes timestamps into frozen copies so jobs cannot mutate caller-owned Time objects.
      class TimestampNormalizer
        def initialize(name, value)
          @name = name
          @value = value
        end

        def normalize
          return value.dup.freeze if value.is_a?(Time)

          raise InvalidJobAttributeError, "#{name} must be a Time"
        end

        private

        attr_reader :name, :value
      end

      private_constant :IdentifierNormalizer, :TimestampNormalizer
    end

    # Normalizes and deeply freezes job arguments so job instances remain immutable.
    class ImmutableArguments
      IMMUTABLE_SCALAR_CLASSES = [NilClass, Numeric, Symbol, TrueClass, FalseClass].freeze
      DUPLICABLE_SCALAR_CLASSES = [String, Time].freeze
      private_constant :IMMUTABLE_SCALAR_CLASSES
      private_constant :DUPLICABLE_SCALAR_CLASSES

      def initialize(arguments)
        @arguments = arguments
      end

      def normalize
        raise InvalidJobAttributeError, 'arguments must be a Hash' unless arguments.is_a?(Hash)
        return arguments if NormalizedGraph.new(
          arguments,
          immutable_scalar_checker: method(:immutable_scalar?),
          duplicable_scalar_checker: method(:duplicable_scalar?)
        ).normalized?

        freeze_hash(arguments, tracker: TraversalTracker.new)
      end

      private

      attr_reader :arguments

      def freeze_hash(value, tracker:)
        tracker.around(value) do
          value.each_with_object({}) do |(key, item), normalized|
            normalized_key = key.to_s.strip
            raise InvalidJobAttributeError, 'argument keys must be present' if normalized_key.empty?

            normalized_key = normalized_key.freeze
            if normalized.key?(normalized_key)
              raise InvalidJobAttributeError,
                    "duplicate argument key after normalization: #{normalized_key.inspect}"
            end

            normalized[normalized_key] = freeze_value(item, tracker:)
          end.freeze
        end
      end

      def freeze_value(value, tracker:)
        case value
        when Hash
          freeze_hash(value, tracker:)
        when Array
          freeze_array(value, tracker:)
        else
          freeze_scalar(value)
        end
      end

      def freeze_array(value, tracker:)
        tracker.around(value) do
          value.map { |item| freeze_value(item, tracker:) }.freeze
        end
      end

      def freeze_scalar(value)
        duplicable = duplicable_scalar?(value)
        return value if immutable_scalar?(value)
        return value if value.frozen? && duplicable
        return value.dup.freeze if duplicable

        raise InvalidJobAttributeError,
              'argument values must be composed of Hash, Array, String, Time, Symbol, Numeric, boolean, or nil'
      end

      def self.immutable_scalar?(value)
        IMMUTABLE_SCALAR_CLASSES.any? { |klass| value.is_a?(klass) }
      end

      private_class_method :immutable_scalar?

      def self.duplicable_scalar?(value)
        DUPLICABLE_SCALAR_CLASSES.any? { |klass| value.is_a?(klass) }
      end

      private_class_method :duplicable_scalar?

      def immutable_scalar?(value)
        self.class.send(:immutable_scalar?, value)
      end

      def duplicable_scalar?(value)
        self.class.send(:duplicable_scalar?, value)
      end

      # Tracks container objects during traversal so recursive argument graphs
      # can be rejected before they blow the Ruby stack.
      class TraversalTracker
        def initialize
          @entered_object_ids = {}
        end

        def track(value)
          object_id = value.object_id
          raise InvalidJobAttributeError, 'arguments must not contain recursive structures' if entered_object_ids.key?(object_id)

          entered_object_ids[object_id] = true
        end

        def around(value)
          track(value)
          yield
        ensure
          leave(value)
        end

        def leave(value)
          entered_object_ids.delete(value.object_id)
        end

        private

        attr_reader :entered_object_ids
      end

      private_constant :TraversalTracker

      # Detects whether a value graph is already in the canonical immutable form.
      class NormalizedGraph
        def initialize(value, immutable_scalar_checker:, duplicable_scalar_checker:)
          @value = value
          @immutable_scalar_checker = immutable_scalar_checker
          @duplicable_scalar_checker = duplicable_scalar_checker
        end

        def normalized?
          normalized_value?(value, tracker: TraversalTracker.new)
        end

        private

        attr_reader :duplicable_scalar_checker, :immutable_scalar_checker, :value

        def normalized_value?(candidate, tracker:)
          frozen_candidate = candidate.frozen?

          case candidate
          when Hash
            normalized_hash?(candidate, frozen_candidate:, tracker:)
          when Array
            normalized_array?(candidate, frozen_candidate:, tracker:)
          else
            immutable_scalar?(candidate) || (duplicable_scalar?(candidate) && frozen_candidate)
          end
        end

        def normalized_hash?(candidate, frozen_candidate:, tracker:)
          tracker.around(candidate) do
            frozen_candidate &&
              candidate.all? do |key, item|
                NormalizedKey.new(key).valid? && normalized_value?(item, tracker:)
              end
          end
        end

        def normalized_array?(candidate, frozen_candidate:, tracker:)
          tracker.around(candidate) do
            frozen_candidate && candidate.all? { |item| normalized_value?(item, tracker:) }
          end
        end

        def immutable_scalar?(candidate)
          immutable_scalar_checker.call(candidate)
        end

        def duplicable_scalar?(candidate)
          duplicable_scalar_checker.call(candidate)
        end

        # Validates that normalized argument keys are frozen, non-empty strings.
        class NormalizedKey
          def initialize(key)
            @key = key
          end

          def valid?
            return false unless key.is_a?(String) && key.frozen?

            stripped = key.strip
            !stripped.empty? && stripped == key
          end

          private

          attr_reader :key
        end

        private_constant :NormalizedKey
      end

      private_constant :NormalizedGraph
    end

    private_constant :Attributes, :ImmutableArguments
  end
end
