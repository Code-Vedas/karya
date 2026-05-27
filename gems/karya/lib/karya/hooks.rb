# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  # Small process-wide hook registry for framework/runtime integration events.
  module Hooks
    EVENTS = %i[
      runtime_build
      runtime_start
      runtime_stop
      operator_authorization
      active_job_enqueue
      active_job_execute
    ].freeze

    module_function

    def register(event, hook = nil, &block)
      normalized_event = normalize_event(event)
      normalized_hook = normalize_hook(hook, block)
      registry.fetch(normalized_event) << normalized_hook
      normalized_hook
    end

    def listeners(event)
      registry.fetch(normalize_event(event)).dup.freeze
    end

    def dispatch(event, payload:)
      listeners(event).each { |hook| hook.call(payload) }
      nil
    end

    def dispatch_authorization(payload:, default:)
      listeners(:operator_authorization).reduce(default) do |decision, hook|
        hook_decision = hook.call(payload.merge('authorized' => decision))
        { nil => decision }.fetch(hook_decision) { !!hook_decision }
      end
    end

    def reset!
      @registry = nil
    end

    def normalize_event(event)
      normalized_event = event.to_sym
      return normalized_event if EVENTS.include?(normalized_event)

      raise ArgumentError, "unsupported Karya hook event #{event.inspect}"
    end
    private_class_method :normalize_event

    def normalize_hook(hook = nil, block = nil)
      normalized_hook = hook || block
      normalized_hook&.public_method(:call) || raise(NameError)
      normalized_hook
    rescue NameError
      raise ArgumentError, 'Karya hook must respond to #call'
    end
    private_class_method :normalize_hook

    def registry
      @registry ||= EVENTS.to_h { |event| [event, []] }
    end
    private_class_method :registry
  end
end
