# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'internal/active_job_loader'

module Karya
  # ActiveJob compatibility bridge for Rails-first hosts.
  module ActiveJob
    # Dispatches serialized ActiveJob payloads back through ActiveJob execution.
    module Handler
      NAME = 'active_job'

      module_function

      def call(job_data:)
        Karya::Internal::ActiveJobLoader.require!
        Karya::Hooks.dispatch('active_job_execute', payload: { 'job_data' => job_data })
        ::ActiveJob::Base.execute(job_data)
      end
    end

    # Queue adapter that persists serialized ActiveJob payloads through Karya.
    class QueueAdapter
      def enqueue(job)
        current_time = Time.now.utc
        self.class.enqueue_job(job, now: current_time)
        Karya::Hooks.dispatch('active_job_enqueue', payload: hook_payload_for(job:, scheduled_at: nil))
      end

      def enqueue_after_transaction_commit?
        # The bridge hands jobs to Karya at enqueue time; app-owned commit
        # coordination belongs at the host boundary.
        false
      end

      def enqueue_at(job, timestamp)
        current_time = Time.now.utc
        scheduled_at = Time.at(timestamp.to_f).utc
        Karya.enqueue_at(
          queue: queue_name_for(job),
          handler: Handler::NAME,
          arguments: karya_arguments_for(job),
          at: scheduled_at,
          now: current_time,
          job_id: job_id_for(job)
        )
        Karya::Hooks.dispatch('active_job_enqueue', payload: hook_payload_for(job:, scheduled_at:))
      end

      class << self
        def enqueue_job(job, now:)
          Karya.enqueue(
            queue: queue_name_for(job),
            handler: Handler::NAME,
            arguments: karya_arguments_for(job),
            now:,
            job_id: job_id_for(job)
          )
        end

        def hook_payload_for(job:, scheduled_at:)
          payload = {
            'job_id' => job_id_for(job),
            'queue' => queue_name_for(job),
            'handler' => Handler::NAME
          }
          payload['scheduled_at'] = scheduled_at.iso8601 if scheduled_at
          payload
        end

        private

        def job_id_for(job)
          job.job_id
        end

        def queue_name_for(job)
          job.queue_name
        end

        def karya_arguments_for(job)
          { 'job_data' => job.serialize }
        end
      end

      private

      def hook_payload_for(job:, scheduled_at:)
        self.class.hook_payload_for(job:, scheduled_at:)
      end

      def job_id_for(job)
        self.class.send(:job_id_for, job)
      end

      def queue_name_for(job)
        self.class.send(:queue_name_for, job)
      end

      def karya_arguments_for(job)
        self.class.send(:karya_arguments_for, job)
      end
    end

    class << self
      def queue_adapter
        Karya::Internal::ActiveJobLoader.require!
        QueueAdapter.new
      end

      def handler
        Handler.method(:call)
      end

      def handler_name
        Handler::NAME
      end
    end
  end
end
