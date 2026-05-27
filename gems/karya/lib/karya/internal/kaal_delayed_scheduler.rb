# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    # Schedules delayed Karya enqueues through Kaal when delayed-job support is available.
    class KaalDelayedScheduler
      class << self
        def schedule(queue:, handler:, arguments:, job_id:, created_at:, scheduled_at:)
          queue_label = queue.inspect
          handler_label = handler.inspect

          unless configured_kaal_backend
            raise UnsupportedSchedulingError,
                  "scheduled enqueue requires Kaal with delayed-job support for #{queue_label} / #{handler_label} at #{scheduled_at}"
          end

          payload = delayed_enqueue_job_class.serialize_request(
            queue:,
            handler:,
            arguments:,
            job_id:,
            created_at:,
            scheduled_at:
          )

          Kaal.enqueue_at(
            at: scheduled_at,
            job_class: delayed_enqueue_job_class,
            args: [payload],
            queue: nil,
            job_id:
          )
        rescue StandardError => e
          raise unless unsupported_scheduler_error?(e)

          raise UnsupportedSchedulingError,
                "scheduled enqueue is unavailable for #{queue_label} / #{handler_label} at #{scheduled_at}: #{e.message}"
        end

        private

        def configured_kaal_backend
          return unless defined?(::Kaal)

          ::Kaal.method(:enqueue_at)
          backend = Kaal.configuration.backend
          delayed_store = backend.delayed_store
          return unless delayed_store

          backend
        rescue ArgumentError, NameError
          nil
        end

        def delayed_enqueue_job_class
          require_relative 'delayed_enqueue_job'
          DelayedEnqueueJob
        end

        def unsupported_scheduler_error?(error)
          (defined?(::Kaal) && error.is_a?(Kaal::SchedulerConfigError)) ||
            error.is_a?(ArgumentError)
        end
      end
    end
  end
end
