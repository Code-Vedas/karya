# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'rails/command'
require 'rails/command/environment_argument'
require 'karya/rails'

module Rails
  module Command
    # Runs framework-native Karya workers from a Rails app.
    class KaryaCommand < Base
      include EnvironmentArgument

      class_option :name, type: :string, desc: 'Logical worker name used for runtime control'
      class_option :processes, type: :numeric, desc: 'Number of supervisor child processes'
      class_option :threads, type: :numeric, desc: 'Number of worker threads per child process'
      class_option :lease_duration, type: :numeric, desc: 'Reservation lease duration in seconds'
      class_option :poll_interval, type: :numeric, desc: 'Worker poll interval in seconds'
      class_option :default_execution_timeout, type: :numeric, desc: 'Default execution timeout in seconds'
      class_option :max_iterations, type: :numeric, desc: 'Maximum work loop iterations before exit'
      class_option :stop_when_idle, type: :boolean, desc: 'Exit once the selected queues are idle'
      class_option :include_active_job, type: :boolean, default: true, desc: 'Register the ActiveJob bridge handler'

      desc 'work QUEUE [QUEUE ...]', 'Run a Karya worker for the given queues'
      def work(*queues)
        raise Error, 'at least one queue is required' if queues.empty?

        boot_application!
        ::Karya::Rails.support.run_worker(
          queues:,
          name: options[:name],
          extra_handlers: active_job_handlers,
          eager_load: -> { ::Rails.application.eager_load! },
          **worker_options
        )
      end

      private

      def active_job_handlers
        return {} unless options.fetch(:include_active_job)

        { ::Karya::ActiveJob.handler_name => ::Karya::Rails.active_job_handler }
      end

      def worker_options
        ::Karya::FrameworkJob::RuntimeOptions.compact(
          processes: options[:processes],
          threads: options[:threads],
          lease_duration: options[:lease_duration],
          poll_interval: options[:poll_interval],
          default_execution_timeout: options[:default_execution_timeout],
          max_iterations: options[:max_iterations],
          stop_when_idle: options[:stop_when_idle]
        )
      end
    end
  end
end
