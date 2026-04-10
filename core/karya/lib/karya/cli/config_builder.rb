# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class CLI < Thor
    # Normalizes CLI worker boot options into a supervisor configuration hash.
    class ConfigBuilder
      def self.build(options:, queues:, queue_store:, defaults:, helpers:)
        new(options:, queues:, queue_store:, defaults:, helpers:).build
      end

      def initialize(options:, queues:, queue_store:, defaults:, helpers:)
        @options = options
        @queues = queues
        @queue_store = queue_store
        @defaults = defaults
        @helpers = helpers
      end

      def build
        env_prefix = helpers.fetch(:normalize_env_prefix_option).call(:env_prefix)
        {
          queue_store:,
          **resolved_process_settings(env_prefix),
          state_file: options.fetch(:state_file, nil),
          worker_id: options.fetch(:worker_id),
          queues:,
          handlers: HandlerParser.parse(options.fetch(:handler)),
          lease_duration: options.fetch(:lease_duration),
          default_execution_timeout: options.fetch(:default_execution_timeout, nil),
          poll_interval: options.fetch(:poll_interval),
          max_iterations: helpers.fetch(:coerce_optional_positive_integer_option).call(:max_iterations),
          stop_when_idle: options.fetch(:stop_when_idle),
          signal_subscriber: SignalSubscription.method(:subscribe)
        }
      end

      private

      attr_reader :defaults, :helpers, :options, :queue_store, :queues

      def resolved_process_settings(env_prefix)
        resolve_positive_integer_option = helpers.fetch(:resolve_positive_integer_option)
        {
          processes: resolve_positive_integer_option.call(:processes, env_prefix:, defaults:),
          threads: resolve_positive_integer_option.call(:threads, env_prefix:, defaults:)
        }
      end
    end
  end
end
