# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      # Builds one durable policy-state row from queue-store runtime maps.
      class PolicyStateRecord
        QUEUE_SCOPE_PREFIX = 'queue:'
        HANDLER_SCOPE_PREFIX = 'handler:'
        TENANT_SCOPE_PREFIX = 'tenant:'
        WORKFLOW_SCOPE_PREFIX = 'workflow:'
        private_constant :HANDLER_SCOPE_PREFIX, :QUEUE_SCOPE_PREFIX, :TENANT_SCOPE_PREFIX, :WORKFLOW_SCOPE_PREFIX

        def initialize(namespace:, policy_kind:, scope:, state_payload:, updated_at:)
          @namespace = namespace
          @policy_kind = policy_kind
          @scope_kind = scope.fetch(:kind)
          @scope_value = scope.fetch(:value)
          @state_payload = state_payload
          @updated_at = updated_at
        end

        def to_h
          {
            namespace:,
            policy_kind:,
            scope_kind:,
            scope_value:,
            state_payload: PayloadCodec.dump(state_payload),
            updated_at:
          }
        end

        def self.scope_components(scope_key)
          return ['queue', ''] if scope_key == ''
          return ['queue', scope_key.delete_prefix(QUEUE_SCOPE_PREFIX)] if scope_key.start_with?(QUEUE_SCOPE_PREFIX)
          return ['handler', scope_key.delete_prefix(HANDLER_SCOPE_PREFIX)] if scope_key.start_with?(HANDLER_SCOPE_PREFIX)
          return ['tenant', scope_key.delete_prefix(TENANT_SCOPE_PREFIX)] if scope_key.start_with?(TENANT_SCOPE_PREFIX)
          return ['workflow', scope_key.delete_prefix(WORKFLOW_SCOPE_PREFIX)] if scope_key.start_with?(WORKFLOW_SCOPE_PREFIX)

          kind, value = scope_key.split(':', 2)
          return ['custom', scope_key] unless value

          [kind, value]
        end

        def self.stringify_payload(value)
          value.to_h.each_with_object({}) do |(key, item), normalized|
            normalized[key.to_s] = normalize_value(item)
          end.freeze
        end

        private

        attr_reader :namespace, :policy_kind, :scope_kind, :scope_value, :state_payload, :updated_at

        def self.normalize_value(value)
          case value
          when Symbol
            value.to_s
          when Array
            value.map { |item| normalize_value(item) }.freeze
          when Hash
            stringify_payload(value)
          else
            value
          end
        end
        private_class_method :normalize_value
      end
    end
  end
end
