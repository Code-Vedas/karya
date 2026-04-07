# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class WorkerSupervisor
    # Immutable runtime inspection snapshot for the supervisor-managed topology.
    class RuntimeSnapshot
      # Immutable child-thread snapshot.
      class ThreadSnapshot
        attr_reader :state, :worker_id

        def initialize(worker_id:, state:)
          @worker_id = worker_id.freeze
          @state = state.freeze
          freeze
        end

        def to_h
          {
            worker_id:,
            state:
          }
        end
      end

      # Immutable child-process snapshot.
      class ChildProcessSnapshot
        attr_reader :pid, :state, :thread_count, :threads

        def initialize(pid:, state:, thread_count:, threads:)
          @pid = pid
          @state = state.freeze
          @thread_count = thread_count
          @threads = threads.freeze
          freeze
        end

        def to_h
          {
            pid:,
            state:,
            thread_count:,
            threads: threads.map(&:to_h)
          }
        end
      end

      attr_reader :configured_processes, :configured_threads, :phase, :queues, :supervisor_pid, :worker_id, :child_processes

      def self.from_h(payload)
        new(
          worker_id: fetch_value(payload, 'worker_id'),
          supervisor_pid: fetch_value(payload, 'supervisor_pid'),
          queues: fetch_value(payload, 'queues'),
          configured_processes: fetch_value(payload, 'configured_processes'),
          configured_threads: fetch_value(payload, 'configured_threads'),
          phase: fetch_value(payload, 'phase'),
          child_processes: child_processes_from(payload)
        )
      end

      def initialize(attributes)
        @worker_id = attributes.fetch(:worker_id).freeze
        @supervisor_pid = attributes.fetch(:supervisor_pid)
        @queues = attributes.fetch(:queues).freeze
        @configured_processes = attributes.fetch(:configured_processes)
        @configured_threads = attributes.fetch(:configured_threads)
        @phase = attributes.fetch(:phase).freeze
        @child_processes = attributes.fetch(:child_processes).freeze
        freeze
      end

      def to_h
        {
          worker_id:,
          supervisor_pid:,
          queues:,
          configured_processes:,
          configured_threads:,
          phase:,
          child_processes: child_processes.map(&:to_h)
        }
      end

      class << self
        private

        def child_processes_from(payload)
          Array(fetch_optional_value(payload, 'child_processes', [])).map do |child_payload|
            ChildProcessSnapshot.new(
              pid: fetch_value(child_payload, 'pid'),
              state: fetch_value(child_payload, 'state'),
              thread_count: fetch_value(child_payload, 'thread_count'),
              threads: threads_from(child_payload)
            )
          end
        end

        def threads_from(child_payload)
          Array(fetch_optional_value(child_payload, 'threads', [])).map do |thread_payload|
            ThreadSnapshot.new(
              worker_id: fetch_value(thread_payload, 'worker_id'),
              state: fetch_value(thread_payload, 'state')
            )
          end
        end

        def fetch_optional_value(payload, key, default)
          symbol_key = key.to_sym
          return payload.fetch(key) if payload.key?(key)
          return payload.fetch(symbol_key) if payload.key?(symbol_key)

          default
        end

        def fetch_value(payload, key)
          return payload.fetch(key) if payload.key?(key)

          payload.fetch(key.to_sym)
        end
      end
    end
  end
end
