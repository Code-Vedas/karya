# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Hanami
    module CLI
      # Framework-native Hanami worker command.
      class Work < ::Hanami::CLI::Commands::App::Command
        desc 'Run a Karya worker for the given comma-separated queues'

        argument :queues, required: true, desc: 'Comma-separated queue names'
        option :name, required: false, desc: 'Logical worker name used for runtime control'
        option :processes, required: false, desc: 'Number of supervisor child processes'
        option :threads, required: false, desc: 'Number of worker threads per child process'
        option :lease_duration, required: false, desc: 'Reservation lease duration in seconds'
        option :poll_interval, required: false, desc: 'Worker poll interval in seconds'
        option :default_execution_timeout, required: false, desc: 'Default execution timeout in seconds'
        option :max_iterations, required: false, desc: 'Maximum work loop iterations before exit'
        option :stop_when_idle, required: false, desc: 'Exit once the selected queues are idle', type: :boolean

        def initialize(framework: Karya::Hanami, runtime_options: Karya::FrameworkJob::RuntimeOptions, **)
          super(**)
          @framework = framework
          @runtime_options = runtime_options
        end

        def call(queues:, **options)
          framework.load_config_file!
          worker_name = options[:name]
          runtime_options_hash = runtime_options.compact(options.except(:name))
          worker_options = { queues: Karya::Internal::FrameworkRuntimeIdentity.parse_queues(queues) }
          worker_options[:name] = worker_name if worker_name
          framework.support.run_worker(**worker_options, **runtime_options_hash)
        end

        private

        attr_reader :framework, :runtime_options
      end
    end
  end
end
