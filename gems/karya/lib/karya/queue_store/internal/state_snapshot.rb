# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    module Internal
      # Encodes the durable queue-store state payload shared by durable adapters.
      module StateSnapshot
        require 'bigdecimal'
        require 'json'
        require 'time'
        require_relative '../internal'
        require_relative '../../job_lifecycle'

        SUPPORTED_KARYA_CLASS_PREFIXES = [
          'Karya::QueueStore::Internal::',
          'Karya::Workflow::'
        ].freeze
        SUPPORTED_KARYA_CLASS_NAMES = [
          'Karya::Backpressure::Scope',
          'Karya::Reservation',
          'Karya::RetryPolicy'
        ].freeze
        SUPPORTED_SYMBOLS = {
          'state' => :state,
          'reservation_token_sequence' => :reservation_token_sequence,
          'applied_version' => :applied_version,
          'id' => :id,
          'queue' => :queue,
          'handler' => :handler,
          'arguments' => :arguments,
          'priority' => :priority,
          'concurrency_scope' => :concurrency_scope,
          'rate_limit_scope' => :rate_limit_scope,
          'retry_policy' => :retry_policy,
          'execution_timeout' => :execution_timeout,
          'expires_at' => :expires_at,
          'idempotency_key' => :idempotency_key,
          'uniqueness_key' => :uniqueness_key,
          'uniqueness_scope' => :uniqueness_scope,
          'lifecycle_extensions' => :lifecycle_extensions,
          'state_names' => :state_names,
          'terminal_state_names' => :terminal_state_names,
          'transitions' => :transitions,
          'attempt' => :attempt,
          'created_at' => :created_at,
          'enqueued_at' => :enqueued_at,
          'updated_at' => :updated_at,
          'next_retry_at' => :next_retry_at,
          'failure_classification' => :failure_classification,
          'dead_letter_reason' => :dead_letter_reason,
          'dead_lettered_at' => :dead_lettered_at,
          'dead_letter_source_state' => :dead_letter_source_state,
          'token' => :token,
          'job_id' => :job_id,
          'worker_id' => :worker_id,
          'reserved_at' => :reserved_at,
          'max_attempts' => :max_attempts,
          'base_delay' => :base_delay,
          'multiplier' => :multiplier,
          'max_delay' => :max_delay,
          'jitter_strategy' => :jitter_strategy,
          'escalate_on' => :escalate_on,
          'name' => :name,
          'kind' => :kind,
          'value' => :value,
          'decided_at' => :decided_at,
          'reason' => :reason,
          'cooldown_until' => :cooldown_until,
          'recovery_count' => :recovery_count,
          'last_recovered_at' => :last_recovered_at,
          'last_recovery_reason' => :last_recovery_reason,
          'submission' => :submission,
          'queued' => :queued,
          'reserved' => :reserved,
          'running' => :running,
          'succeeded' => :succeeded,
          'failed' => :failed,
          'retry_pending' => :retry_pending,
          'dead_letter' => :dead_letter,
          'cancelled' => :cancelled,
          'error' => :error,
          'timeout' => :timeout,
          'expired' => :expired,
          'none' => :none,
          'full' => :full,
          'equal' => :equal,
          'approved' => :approved,
          'rejected' => :rejected,
          'signal' => :signal,
          'event' => :event,
          'workflow' => :workflow,
          'step' => :step,
          'interaction' => :interaction,
          'control' => :control,
          'rollback' => :rollback,
          'child_workflow' => :child_workflow,
          'tenant' => :tenant,
          'custom' => :custom,
          'open' => :open,
          'half_open' => :half_open,
          'active' => :active,
          'until_terminal' => :until_terminal
        }.freeze

        # Owner-local JSON codec that restores only Karya-owned queue-store objects.
        module JsonCodec
          TYPE_KEY = '__karya_type__'
          CLASS_KEY = 'class'
          ENTRIES_KEY = 'entries'
          ITEMS_KEY = 'items'
          VALUE_KEY = 'value'
          IVARS_KEY = 'ivars'
          FROZEN_KEY = 'frozen'
          JOB_ATTRIBUTES_KEY = 'attributes'
          NUMERATOR_KEY = 'numerator'
          DENOMINATOR_KEY = 'denominator'
          SCALAR_CLASSES = [NilClass, TrueClass, FalseClass, Integer, Float, String].freeze

          module_function

          def dump(payload)
            JSON.generate(encode_value(payload))
          end

          def load(payload)
            decode_value(JSON.parse(payload))
          rescue JSON::ParserError, KeyError, TypeError, NoMethodError, ArgumentError => e
            raise InvalidQueueStoreOperationError, "invalid queue-store state snapshot: #{e.class}: #{e.message}", cause: e
          end

          def encode_value(value)
            scalar_value = encode_scalar_value(value)
            return scalar_value unless scalar_value.equal?(self)

            case value
            when Array
              encode_array(value)
            when Hash
              encode_hash(value)
            when Struct
              encode_karya_struct(value)
            when Karya::Job
              validate_supported_job_arguments!(value.arguments)
              tagged('job', JOB_ATTRIBUTES_KEY => encode_value(value.send(:marshal_dump)))
            else
              encode_karya_object(value)
            end
          end

          def encode_scalar_value(value)
            case value
            when *SCALAR_CLASSES
              validate_supported_float!(value) if value.is_a?(Float)
              value
            when Symbol
              encode_string_scalar('symbol', value)
            when Time
              tagged('time', VALUE_KEY => value.iso8601(9))
            when BigDecimal
              encode_string_scalar('bigdecimal', value)
            when Rational
              tagged('rational', NUMERATOR_KEY => value.numerator, DENOMINATOR_KEY => value.denominator)
            else
              self
            end
          end

          def decode_value(value)
            case value
            when NilClass, TrueClass, FalseClass, Integer, Float
              value
            when String
              value.dup.freeze
            when Array
              value.map { |item| decode_value(item) }
            when Hash
              decode_tagged_value(value)
            else
              unsupported_payload!(value.class)
            end
          end

          def encode_karya_object(value)
            object_class = value.class
            unsupported_payload!(object_class) unless karya_object?(object_class)

            tagged(
              'object',
              CLASS_KEY => object_class.name,
              IVARS_KEY => value.instance_variables.to_h do |name|
                [name.to_s, encode_value(value.instance_variable_get(name))]
              end,
              FROZEN_KEY => value.frozen?
            )
          end

          def encode_karya_struct(value)
            object_class = value.class
            unsupported_payload!(object_class) unless karya_object?(object_class)

            tagged(
              'struct',
              CLASS_KEY => object_class.name,
              VALUE_KEY => value.each_pair.to_h do |name, member_value|
                [name.to_s, encode_value(member_value)]
              end,
              FROZEN_KEY => value.frozen?
            )
          end

          def decode_tagged_value(value)
            type = value[TYPE_KEY]
            return decode_plain_hash(value) unless type

            decode_known_tagged_value(type, value)
          end

          def decode_plain_hash(value)
            value.transform_values { |item| decode_value(item) }
          end

          def decode_known_tagged_value(type, value)
            case type
            when 'symbol', 'time', 'bigdecimal' then decode_scalar_tag(type, value.fetch(VALUE_KEY))
            when 'rational' then Rational(value.fetch(NUMERATOR_KEY), value.fetch(DENOMINATOR_KEY))
            when 'array' then decode_tagged_array(value)
            when 'hash' then decode_tagged_hash(value)
            when 'job' then decode_tagged_job(value)
            when 'struct' then decode_karya_struct(value)
            when 'object' then decode_karya_object(value)
            else
              raise InvalidQueueStoreOperationError, "unsupported queue-store state snapshot payload type: #{type.inspect}"
            end
          end

          def decode_scalar_tag(type, value)
            return decode_supported_symbol(value) if type == 'symbol'
            return BigDecimal(value) if type == 'bigdecimal'

            Time.iso8601(value)
          end

          def decode_supported_symbol(value)
            StateSnapshot::SUPPORTED_SYMBOLS.fetch(value) { unsupported_symbol!(value) }
          end

          def encode_string_scalar(type, value)
            tagged(type, VALUE_KEY => value.to_s)
          end

          def validate_supported_job_arguments!(arguments)
            validate_argument_value_graph!(arguments)
          end

          def validate_argument_value_graph!(value)
            case value
            when Hash
              recurse_argument_values(value.each_value)
            when Array
              recurse_argument_values(value)
            when Symbol
              raise InvalidQueueStoreOperationError,
                    'queue-store state snapshots do not support Symbol job arguments'
            when Float
              validate_supported_float!(value)
            end
            nil
          end

          def validate_supported_float!(value)
            return if value.finite?

            raise InvalidQueueStoreOperationError,
                  'queue-store state snapshots do not support non-finite Float job arguments'
          end

          def recurse_argument_values(values)
            values.each { |item| validate_argument_value_graph!(item) }
          end

          def encode_array(value)
            encoded_items = value.map { |item| encode_value(item) }
            tagged('array', ITEMS_KEY => encoded_items, FROZEN_KEY => value.frozen?)
          end

          def encode_hash(value)
            encoded_entries = value.map { |key, item| [encode_value(key), encode_value(item)] }
            tagged('hash', ENTRIES_KEY => encoded_entries, FROZEN_KEY => value.frozen?)
          end

          def decode_tagged_array(value)
            restore_frozen(value.fetch(ITEMS_KEY).map { |item| decode_value(item) }, value[FROZEN_KEY])
          end

          def decode_tagged_hash(value)
            decoded_hash = value.fetch(ENTRIES_KEY).to_h do |key, item|
              [decode_value(key), decode_value(item)]
            end
            restore_frozen(decoded_hash, value[FROZEN_KEY])
          end

          def decode_tagged_job(value)
            Karya::Job.allocate.tap do |job|
              job.send(:marshal_load, decode_value(value.fetch(JOB_ATTRIBUTES_KEY)))
            end
          end

          def decode_karya_struct(value)
            klass = resolve_karya_class(value.fetch(CLASS_KEY))
            struct_values = klass.members.map do |member_name|
              decode_value(value.fetch(VALUE_KEY).fetch(member_name.to_s))
            end

            restore_frozen(klass.new(*struct_values), value[FROZEN_KEY])
          end

          def decode_karya_object(value)
            klass = resolve_karya_class(value.fetch(CLASS_KEY))
            object = klass.allocate

            value.fetch(IVARS_KEY).each do |name, item|
              object.instance_variable_set(name, decode_value(item))
            end

            restore_frozen(object, value[FROZEN_KEY])
          end

          def resolve_karya_class(class_name)
            with_supported_class_name(class_name) do
              klass = class_name.split('::').drop(1).reduce(Karya) do |namespace, name|
                namespace.const_get(name, false)
              end
              unsupported_class!(class_name) unless supported_karya_class?(klass)

              klass
            end
          end

          def karya_object?(object_class)
            class_name = object_class.name
            class_name && supported_karya_class_name?(class_name)
          end

          def supported_karya_class?(klass)
            class_name = klass.name
            class_name && supported_karya_class_name?(class_name)
          end

          def supported_karya_class_name?(class_name)
            StateSnapshot::SUPPORTED_KARYA_CLASS_NAMES.include?(class_name) ||
              StateSnapshot::SUPPORTED_KARYA_CLASS_PREFIXES.any? { |prefix| class_name.start_with?(prefix) }
          end

          def restore_frozen(value, frozen)
            frozen ? value.freeze : value
          end

          def tagged(type, payload)
            payload.merge(TYPE_KEY => type)
          end

          def unsupported_payload!(payload_class)
            raise InvalidQueueStoreOperationError, "unsupported queue-store state snapshot payload: #{payload_class}"
          end

          def unsupported_class!(class_name)
            raise InvalidQueueStoreOperationError, "unsupported queue-store state snapshot class: #{class_name.inspect}"
          end

          def unsupported_symbol!(value)
            raise InvalidQueueStoreOperationError, "unsupported queue-store state snapshot symbol: #{value.inspect}"
          end

          def with_supported_class_name(class_name)
            validate_supported_class_name!(class_name)

            yield
          rescue NameError
            unsupported_class!(class_name)
          end

          def validate_supported_class_name!(class_name)
            unsupported_class!(class_name) unless class_name.start_with?('Karya::')
          end
        end
        private_constant :JsonCodec

        module_function

        STORE_STATE_CLASS = Karya::QueueStore::Internal.const_get(:StoreState, false)
        private_constant :STORE_STATE_CLASS

        def dump(state:, reservation_token_sequence:, applied_version:)
          JsonCodec.dump(
            state:,
            reservation_token_sequence:,
            applied_version:
          )
        end

        def dump_payload(payload)
          JsonCodec.dump(payload)
        end

        def load(payload)
          snapshot = JsonCodec.load(payload)
          validate_snapshot(snapshot)
        end

        def load_payload(payload)
          JsonCodec.load(payload)
        end

        def validate_snapshot(snapshot)
          unless snapshot.is_a?(Hash) &&
                 snapshot.fetch(:state).is_a?(STORE_STATE_CLASS) &&
                 snapshot.fetch(:reservation_token_sequence).is_a?(Integer) &&
                 snapshot.fetch(:applied_version).is_a?(Integer)
            invalid_snapshot!
          end

          snapshot
        rescue KeyError
          invalid_snapshot!
        end

        def invalid_snapshot!
          raise InvalidQueueStoreOperationError, 'invalid queue-store state snapshot'
        end
      end
    end
  end
end
