# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'
require_relative 'internal/queue_store_binding'

module Karya
  # Shared framework-facing runtime/bootstrap contract for host integrations.
  module FrameworkRuntime
    # Raised when a host asks for runtime integration before Karya has a backend configured.
    class MissingBackendError < Error; end

    # Started host runtime wrapper used by framework integrations.
    class HostRuntime
      DEFAULT_LEASE_DURATION = 60

      def initialize(backend_class:, backend_options:)
        @backend_class = backend_class
        @backend_options = backend_options
        @queue_store = nil
        @previous_queue_store = nil
        @queue_store_attached = false
        @started = false
      end

      attr_reader :backend, :queue_store

      def start
        return self if @started

        @backend = backend_class.new(**backend_options)
        @queue_store = backend.build_queue_store
        capture_previous_queue_store
        Karya.configure_queue_store(@queue_store)
        @queue_store_attached = true
        backend.before_start(queue_store:)
        @started = true
        Hooks.dispatch('runtime_start', payload: runtime_payload)
        self
      end

      def stop
        return nil unless @started

        backend.after_stop(queue_store:)
        Hooks.dispatch('runtime_stop', payload: runtime_payload)
        nil
      ensure
        restore_previous_queue_store if @queue_store_attached
        @backend = nil
        @queue_store = nil
        @queue_store_attached = false
        @started = false
      end

      def started? = @started

      def health_payload
        start unless @started
        {
          'status' => 'ok',
          'backend' => backend.identifier,
          'queue_store' => queue_store.class.name
        }
      end

      def readiness_payload
        start unless @started
        {
          'status' => 'ready',
          'backend' => backend.identifier,
          'queue_store' => queue_store.class.name
        }
      end

      def operator_payload(mount_path: nil)
        start unless @started
        {
          'backend' => backend.identifier,
          'queue_store' => queue_store.class.name,
          'mount_path' => mount_path,
          'runtime_commands' => %w[inspect drain force_stop]
        }.compact
      end

      def runtime_probe_payload(job_prefix:, worker_id:, mount_path: nil, queue: 'dashboard', lease_duration: DEFAULT_LEASE_DURATION, now: Time.now.utc)
        start unless @started
        job = Karya::Job.new(
          id: "#{job_prefix}-#{SecureRandom.uuid}",
          queue: queue,
          handler: 'dashboard_probe',
          state: :submission,
          created_at: now
        )
        queue_store.enqueue(job:, now:)
        reservation = queue_store.reserve(queue:, worker_id:, lease_duration:, now: now + 1)
        {
          'backend' => backend.identifier,
          'job_id' => reservation.job_id,
          'mount_path' => mount_path
        }.compact
      end

      private

      attr_reader :backend_class, :backend_options

      def runtime_payload
        payload = {
          'backend_class' => backend_class.name,
          'backend_options' => backend_options
        }
        payload['backend'] = backend.identifier if backend
        payload['queue_store'] = queue_store.class.name if queue_store
        payload
      end

      def capture_previous_queue_store
        @previous_queue_store = Karya::Internal::QueueStoreBinding.capture
      end

      def restore_previous_queue_store
        Karya::Internal::QueueStoreBinding.restore(@previous_queue_store)
      end

      def detach_queue_store
        return self unless @started
        return self unless @queue_store_attached

        restore_previous_queue_store
        @queue_store_attached = false
        self
      end
    end

    class << self
      def build(backend_class: Karya.backend_class, backend_options: Karya.backend_options)
        raise MissingBackendError, 'Karya backend must be configured before building framework runtime' unless backend_class

        runtime = HostRuntime.new(backend_class:, backend_options:)
        Hooks.dispatch(
          'runtime_build',
          payload: {
            'backend_class' => backend_class.name,
            'backend_options' => backend_options
          }
        )
        runtime
      end

      def with_started_runtime(backend_class: Karya.backend_class, backend_options: Karya.backend_options)
        runtime = build(backend_class:, backend_options:)
        runtime.start
        yield runtime
      ensure
        runtime&.stop
      end

      def shared_runtime(backend_class: Karya.backend_class, backend_options: Karya.backend_options)
        if @shared_runtime&.started? &&
           @shared_runtime_backend_class.equal?(backend_class) &&
           @shared_runtime_backend_options == backend_options
          return @shared_runtime
        end

        reset_shared_runtime!
        @shared_runtime_backend_class = backend_class
        @shared_runtime_backend_options = backend_options
        @shared_runtime = build(backend_class:, backend_options:)
        @shared_runtime.start.__send__(:detach_queue_store)
      end

      def current_runtime
        return @shared_runtime if @shared_runtime&.started?

        nil
      end

      def reset_shared_runtime!
        @shared_runtime&.stop
      ensure
        @shared_runtime = nil
        @shared_runtime_backend_class = nil
        @shared_runtime_backend_options = nil
      end
    end
  end
end
