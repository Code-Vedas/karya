# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    # Shared framework integration support for configuration, workers, and runtime control.
    class FrameworkSupport
      def initialize(
        framework_name:,
        job_base:,
        root_path_resolver:,
        environment_name_resolver: -> { Config::RuntimeContext.environment_name_from(ENV) }
      )
        @framework_name = framework_name
        @job_base = job_base
        @root_path_resolver = root_path_resolver
        @environment_name_resolver = environment_name_resolver
        @configuration = FrameworkConfiguration.new
        @config_file_loaded = false
      end

      def load_config_file!(path: 'config/karya.yml')
        Config::FileLoader.new(
          configuration: @configuration,
          runtime_context: runtime_context
        ).load(path:)
        @config_file_loaded = true
        @configuration
      end

      def load_config_file(path: 'config/karya.yml')
        load_config_file!(path:)
      end

      def configure
        yield(configuration) if block_given?
        configuration
      end

      def configuration
        load_config_file! unless @config_file_loaded
        @configuration
      end

      def operator_authorizer
        @operator_authorizer || configuration.operator_authorizer
      end

      def configure_operator_authorizer(authorizer = nil)
        authorizer&.public_method(:call)
        @operator_authorizer = authorizer
      rescue NameError
        raise ArgumentError, 'operator authorizer must respond to #call'
      end

      def operator_access_authorized?(request_context, authorizer: nil)
        resolved_authorizer = authorizer || operator_authorizer || Karya.operator_authorizer
        decision = if resolved_authorizer
                     resolved_authorizer.call(request_context) ? true : false
                   else
                     false
                   end
        Karya::Hooks.dispatch_authorization(
          payload: {
            'framework' => framework_name,
            'request_context' => request_context
          },
          default: decision
        )
      end

      def normalize_queues(value)
        FrameworkRuntimeIdentity.parse_queues(value)
      end

      def framework_root_path
        root_path_resolver.call
      end

      def worker_handlers(root_path: framework_root_path, extra_handlers: {}, eager_load: nil)
        Karya::FrameworkJob::Discovery.new(
          root_path:,
          job_base:,
          job_paths: configuration.job_paths,
          boot_files: configuration.boot_files,
          extra_handlers:,
          eager_load:
        ).handlers
      end

      def run_worker(queues:, name: nil, root_path: framework_root_path, extra_handlers: {}, eager_load: nil, **options)
        normalized_queues = normalize_queues(queues)
        logical_name = FrameworkRuntimeIdentity.worker_name(queues: normalized_queues, name:)
        state_file = FrameworkRuntimeIdentity.ensure_state_directory!(
          FrameworkRuntimeIdentity.state_file(root_path:, queues: normalized_queues, name: logical_name)
        )
        worker_id = options.delete(:worker_id) || FrameworkRuntimeIdentity.worker_id(
          framework_name:,
          queues: normalized_queues,
          name: logical_name
        )

        Karya::FrameworkJob::WorkerRunner.run(
          queues: normalized_queues,
          handlers: worker_handlers(root_path:, extra_handlers:, eager_load:),
          **Karya::FrameworkJob::RuntimeOptions.compact(
            options.merge(worker_id:, state_file:)
          )
        )
      end

      def runtime_state_file(queues:, name: nil, root_path: framework_root_path)
        normalized_queues = normalize_queues(queues)
        FrameworkRuntimeIdentity.state_file(root_path:, queues: normalized_queues, name:)
      end

      def runtime_inspect(queues:, name: nil, root_path: framework_root_path)
        FrameworkRuntimeControl.inspect(state_file: runtime_state_file(queues:, name:, root_path:))
      end

      def runtime_drain(queues:, name: nil, root_path: framework_root_path)
        FrameworkRuntimeControl.drain(state_file: runtime_state_file(queues:, name:, root_path:))
      end

      def runtime_force_stop(queues:, name: nil, root_path: framework_root_path)
        FrameworkRuntimeControl.force_stop(state_file: runtime_state_file(queues:, name:, root_path:))
      end

      private

      attr_reader :environment_name_resolver, :framework_name, :job_base, :root_path_resolver

      def runtime_context
        Config::RuntimeContext.new(
          root_path: framework_root_path,
          environment_name: environment_name_resolver.call
        )
      end
    end
  end
end
