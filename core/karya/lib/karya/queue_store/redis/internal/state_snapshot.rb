# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module QueueStore
    class Redis
      module Internal
        # Encodes the durable queue-store state payload stored in Redis.
        module StateSnapshot
          require 'json'
          require 'time'
          require_relative '../../internal'
          require_relative '../../../job_lifecycle'

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
            SCALAR_CLASSES = [NilClass, TrueClass, FalseClass, Integer, Float, String].freeze
            FORBIDDEN_KARYA_CLASSES = [Karya::JobLifecycle::Registry, Karya::JobLifecycle::StateManager].freeze

            module_function

            def dump(payload)
              JSON.generate(encode_value(payload))
            end

            def load(payload)
              decode_value(JSON.parse(payload))
            rescue JSON::ParserError, KeyError, TypeError, NoMethodError, ArgumentError => e
              raise InvalidQueueStoreOperationError, "invalid Redis state snapshot: #{e.message}"
            end

            def encode_value(value)
              case value
              when *SCALAR_CLASSES
                value
              when Symbol
                tagged('symbol', VALUE_KEY => value.to_s)
              when Time
                tagged('time', VALUE_KEY => value.iso8601(9))
              when Array
                encode_array(value)
              when Hash
                encode_hash(value)
              when Struct
                encode_karya_struct(value)
              when Karya::Job
                tagged('job', JOB_ATTRIBUTES_KEY => encode_value(value.send(:marshal_dump)))
              else
                encode_karya_object(value)
              end
            end

            def decode_value(value)
              case value
              when *SCALAR_CLASSES
                value
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
              when 'symbol', 'time' then decode_scalar_tag(type, value.fetch(VALUE_KEY))
              when 'array' then decode_tagged_array(value)
              when 'hash' then decode_tagged_hash(value)
              when 'job' then decode_tagged_job(value)
              when 'struct' then decode_karya_struct(value)
              when 'object' then decode_karya_object(value)
              else
                raise InvalidQueueStoreOperationError, "unsupported Redis state snapshot payload type: #{type.inspect}"
              end
            end

            def decode_scalar_tag(type, value)
              return value.to_sym if type == 'symbol'

              Time.iso8601(value)
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
                unsupported_class!(class_name) if forbidden_karya_class?(klass)

                klass
              end
            end

            def karya_object?(object_class)
              class_name = object_class.name
              class_name&.start_with?('Karya::') && !forbidden_karya_class?(object_class)
            end

            def forbidden_karya_class?(klass)
              FORBIDDEN_KARYA_CLASSES.include?(klass)
            end

            def restore_frozen(value, frozen)
              frozen ? value.freeze : value
            end

            def tagged(type, payload)
              payload.merge(TYPE_KEY => type)
            end

            def unsupported_payload!(payload_class)
              raise InvalidQueueStoreOperationError, "unsupported Redis state snapshot payload: #{payload_class}"
            end

            def unsupported_class!(class_name)
              raise InvalidQueueStoreOperationError, "unsupported Redis state snapshot class: #{class_name.inspect}"
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

          def dump(state:, reservation_token_sequence:)
            JsonCodec.dump(
              state:,
              reservation_token_sequence:
            )
          end

          def load(payload)
            snapshot = JsonCodec.load(payload)
            validate_snapshot(snapshot)
          end

          def validate_snapshot(snapshot)
            unless snapshot.is_a?(Hash) &&
                   snapshot.fetch(:state).is_a?(STORE_STATE_CLASS) &&
                   snapshot.fetch(:reservation_token_sequence).is_a?(Integer)
              invalid_snapshot!
            end

            snapshot
          rescue KeyError
            invalid_snapshot!
          end

          def invalid_snapshot!
            raise InvalidQueueStoreOperationError, 'invalid Redis state snapshot'
          end
        end
      end
    end
  end
end
