# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../queue_store/in_memory'

module Karya
  module Backend
    # Quick-start backend wrapper around the single-process reference queue store.
    class InMemory
      include Base

      def initialize(queue_store_class: QueueStore::InMemory)
        @queue_store_class = queue_store_class
      end

      CAPABILITIES = Capabilities.new(
        job_persistence: false,
        workflow_state: false,
        schedule_state: false,
        audit_history: false,
        shared_processes: false,
        multi_node: false,
        parity_exceptions: [
          'Jobs, workflow state, schedules, and audit history are process-local and lost on restart',
          'The backend is for quick setup, tests, and ephemeral local runs rather than production-grade deployments'
        ]
      )

      DESCRIPTOR = Descriptor.new(
        identifier: :in_memory,
        classification: :quick_setup_and_run,
        capabilities: CAPABILITIES
      )

      def descriptor
        DESCRIPTOR
      end

      def build_queue_store(**)
        queue_store_class.new(**)
      end

      def before_start(queue_store:)
        _queue_store = queue_store
        nil
      end

      def after_stop(queue_store:)
        _queue_store = queue_store
        nil
      end

      private

      attr_reader :queue_store_class
    end
  end
end
