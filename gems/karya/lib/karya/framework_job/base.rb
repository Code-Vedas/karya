# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../internal/framework_job_registry'
require_relative '../internal/retry_policy_normalizer'

module Karya
  module FrameworkJob
    # Shared base class for framework-native Karya jobs.
    class Base
      DEFAULT_QUEUE = 'default'
      @karya_abstract = true

      # Immutable framework job argument wrapper used by workflow and enqueue APIs.
      class Arguments
        def initialize(args:, kwargs:)
          @payload = ArgumentCodec.dump(args, kwargs)
        end

        def to_payload
          payload
        end

        private

        attr_reader :payload
      end

      # One-shot enqueue request that carries queueing metadata separately from perform arguments.
      class EnqueueRequest
        def initialize(job_class:, queue: nil, **job_options)
          @job_class = job_class
          @queue = queue
          @job_options = job_options.freeze
        end

        def perform_later(*args, **kwargs)
          job_class.enqueue_job(
            args:,
            kwargs:,
            queue:,
            **job_options
          )
        end

        private

        attr_reader :job_class, :job_options, :queue
      end

      class << self
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@karya_abstract, false)
          subclass.instance_variable_set(:@karya_queue_name, nil)
          subclass.instance_variable_set(:@karya_handler_name, nil)
          subclass.instance_variable_set(:@karya_retry_policy, nil)
          subclass.instance_variable_set(:@karya_idempotency_block, nil)
          subclass.instance_variable_set(:@karya_uniqueness_block, nil)
          subclass.instance_variable_set(:@karya_uniqueness_scope, nil)
          definition_location = caller_locations(1).find { |location| location.path != __FILE__ }
          Internal::FrameworkJobRegistry.register(
            subclass,
            source_path: definition_location&.absolute_path || definition_location&.path
          )
        end

        def abstract!
          @karya_abstract = true
        end

        def abstract
          abstract!
        end

        def abstract?
          return @karya_abstract unless instance_variable_get(:@karya_abstract).nil?

          false
        end

        def queue_as(name = nil)
          return queue_name if name.nil?

          @karya_queue_name = normalize_identifier(:queue, name)
        end

        def karya_handler(name = nil)
          return handler_name if name.nil?

          @karya_handler_name = normalize_identifier(:handler, name)
        end

        def queue_name
          return @karya_queue_name if instance_variable_defined?(:@karya_queue_name) && @karya_queue_name

          return superclass.queue_name if superclass.respond_to?(:queue_name)

          DEFAULT_QUEUE
        end

        def handler_name
          return @karya_handler_name if instance_variable_defined?(:@karya_handler_name) && @karya_handler_name

          return normalize_identifier(:handler, name) if name

          raise InvalidJobAttributeError, 'framework job classes must have a constant name or explicit karya_handler'
        end

        def set(queue: nil, job_id: nil, idempotency_key: nil, uniqueness_key: nil, uniqueness_scope: nil)
          validate_enqueueable
          EnqueueRequest.new(
            job_class: self,
            queue:,
            job_id:,
            idempotency_key:,
            uniqueness_key:,
            uniqueness_scope:
          )
        end

        def arguments(*args, **kwargs)
          Arguments.new(args:, kwargs:)
        end

        def retry_with(policy)
          @karya_retry_policy = Karya::Internal::RetryPolicyNormalizer.new(
            policy,
            error_class: InvalidJobAttributeError
          ).normalize
        end

        def idempotent_by(&block)
          @karya_idempotency_block = normalize_enqueue_block(:idempotent_by, block)
        end

        def unique_by(scope:, &block)
          @karya_uniqueness_scope = normalize_identifier(:uniqueness_scope, scope)
          @karya_uniqueness_block = normalize_enqueue_block(:unique_by, block)
        end

        def perform_later(*, **)
          set.perform_later(*, **)
        end

        def perform_now(*, **)
          validate_enqueueable
          new.perform(*, **)
        end

        def build_job(
          arguments_payload:,
          now: Time.now.utc,
          queue: queue_name,
          job_id: nil,
          idempotency_key: nil,
          uniqueness_key: nil,
          uniqueness_scope: nil
        )
          validate_enqueueable
          positional_arguments, keyword_arguments = ArgumentCodec.load(arguments_payload)
          normalized_now = now.is_a?(Time) ? now.utc : Time.at(now.to_f).utc
          normalized_job_id = job_id || SecureRandom.uuid
          normalized_queue = queue || queue_name
          Job.new(
            id: normalized_job_id,
            queue: normalized_queue,
            handler: handler_name,
            arguments: arguments_payload,
            retry_policy: retry_policy,
            idempotency_key: idempotency_key || derive_idempotency_key(positional_arguments, keyword_arguments),
            uniqueness_key: uniqueness_key || derive_uniqueness_key(positional_arguments, keyword_arguments),
            uniqueness_scope: uniqueness_scope || default_uniqueness_scope,
            state: :submission,
            created_at: normalized_now
          )
        end

        def enqueue_job(args:, kwargs:, **)
          job = build_job(arguments_payload: ArgumentCodec.dump(args, kwargs), **)
          Karya._resolve_queue_store.enqueue(job:, now: job.created_at)
          job
        end

        def retry_policy
          configured_or_inherited_value(:@karya_retry_policy, :retry_policy)
        end

        def default_uniqueness_scope
          configured_or_inherited_value(:@karya_uniqueness_scope, :default_uniqueness_scope)
        end

        private

        def validate_enqueueable
          raise InvalidJobAttributeError, "#{self} is abstract and cannot enqueue work" if abstract?

          handler_name
          queue_name
        end

        def normalize_identifier(field_name, value)
          Primitives::Identifier.new(field_name, value, error_class: InvalidJobAttributeError).normalize
        end

        def normalize_enqueue_block(name, block)
          raise InvalidJobAttributeError, "#{name} requires a block" unless block

          block
        end

        def derive_idempotency_key(positional_arguments, keyword_arguments)
          derive_metadata_value(:@karya_idempotency_block, positional_arguments, keyword_arguments)
        end

        def derive_uniqueness_key(positional_arguments, keyword_arguments)
          derive_metadata_value(:@karya_uniqueness_block, positional_arguments, keyword_arguments)
        end

        def derive_metadata_value(name, positional_arguments, keyword_arguments)
          block = metadata_block_for(name) || inherited_metadata_block(name)
          return nil unless block

          block.call(*positional_arguments, **keyword_arguments)
        end

        def metadata_block_for(name)
          instance_variable_defined?(name) ? instance_variable_get(name) : nil
        end

        def configured_or_inherited_value(instance_variable_name, inherited_method_name)
          value = instance_variable_defined?(instance_variable_name) ? instance_variable_get(instance_variable_name) : nil
          return value if value
          return nil unless superclass.respond_to?(inherited_method_name)

          superclass.public_send(inherited_method_name)
        end

        def inherited_metadata_block(name)
          return nil unless superclass.respond_to?(:metadata_block_for, true)

          superclass.send(:metadata_block_for, name)
        end
      end
    end
  end
end
