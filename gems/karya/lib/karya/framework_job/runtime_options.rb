# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module FrameworkJob
    # Normalizes framework wrapper runtime options into worker supervisor kwargs.
    module RuntimeOptions
      OPTION_ENV_KEYS = {
        processes: 'KARYA_PROCESSES',
        threads: 'KARYA_THREADS',
        worker_id: 'KARYA_WORKER_ID',
        lease_duration: 'KARYA_LEASE_DURATION',
        poll_interval: 'KARYA_POLL_INTERVAL',
        default_execution_timeout: 'KARYA_DEFAULT_EXECUTION_TIMEOUT',
        state_file: 'KARYA_STATE_FILE',
        env_prefix: 'KARYA_ENV_PREFIX',
        max_iterations: 'KARYA_MAX_ITERATIONS',
        stop_when_idle: 'KARYA_STOP_WHEN_IDLE'
      }.freeze
      private_constant :OPTION_ENV_KEYS

      module_function

      def compact(options)
        options.each_with_object({}) do |(key, value), normalized|
          normalized[key] = value unless value.nil?
        end
      end

      def from_env(env = ENV)
        compact(
          processes: integer_env_value(env, :processes),
          threads: integer_env_value(env, :threads),
          worker_id: string_env_value(env, :worker_id),
          lease_duration: float_env_value(env, :lease_duration),
          poll_interval: float_env_value(env, :poll_interval),
          default_execution_timeout: float_env_value(env, :default_execution_timeout),
          state_file: string_env_value(env, :state_file),
          env_prefix: string_env_value(env, :env_prefix),
          max_iterations: integer_env_value(env, :max_iterations),
          stop_when_idle: boolean_env_value(env, :stop_when_idle)
        )
      end

      def boolean_value(value)
        return nil if value.nil? || value == ''

        normalized = value.to_s.strip.downcase
        return true if %w[1 true yes on].include?(normalized)
        return false if %w[0 false no off].include?(normalized)

        raise ArgumentError, "invalid boolean value #{value.inspect}"
      end
      module_function :boolean_value

      def integer_value(value)
        return nil if value.nil? || value == ''

        Integer(value, 10)
      end
      module_function :integer_value

      def float_value(value)
        return nil if value.nil? || value == ''

        Float(value)
      end
      module_function :float_value

      def string_value(value)
        return nil if value.nil? || value == ''

        value.to_s
      end
      module_function :string_value

      def raw_env_value(env, key)
        env.fetch(OPTION_ENV_KEYS.fetch(key), nil)
      end
      module_function :raw_env_value

      def boolean_env_value(env, key)
        boolean_value(raw_env_value(env, key))
      end
      module_function :boolean_env_value

      def integer_env_value(env, key)
        integer_value(raw_env_value(env, key))
      end
      module_function :integer_env_value

      def float_env_value(env, key)
        float_value(raw_env_value(env, key))
      end
      module_function :float_env_value

      def string_env_value(env, key)
        string_value(raw_env_value(env, key))
      end
      module_function :string_env_value
    end
  end
end
