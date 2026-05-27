# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'karya'
require 'karya/dashboard'
require_relative 'roda/version'
require_relative 'roda/job'
require_relative 'roda/rake_tasks'
require_relative 'roda/workflow'
module Karya
  # Roda module used to integrate Karya to Roda applications.
  module Roda
    module_function

    DEFAULT_MOUNT_PATH = '/karya'

    def support
      @support ||= Karya::Internal::FrameworkSupport.new(
        framework_name: 'roda',
        job_base: Job,
        root_path_resolver: -> { Dir.pwd },
        environment_name_resolver: -> { ENV.fetch('RACK_ENV', Karya::Internal::Config::RuntimeContext.environment_name_from(ENV)) }
      )
    end

    def build_host_runtime(backend_class: nil, backend_options: nil)
      support.load_config_file!
      backend_class ||= Karya.backend_class
      backend_options ||= Karya.backend_options
      Karya::FrameworkRuntime.build(backend_class:, backend_options:)
    end

    def with_host_runtime(backend_class: nil, backend_options: nil, &)
      support.load_config_file!
      backend_class ||= Karya.backend_class
      backend_options ||= Karya.backend_options
      Karya::FrameworkRuntime.with_started_runtime(backend_class:, backend_options:, &)
    end

    def render_dashboard_page(scope: nil, title: Karya::Dashboard::DEFAULT_TITLE, asset_prefix: nil, name: 'dashboard')
      Karya::Dashboard.render_document(title:, mount_path: mount_path(scope:), asset_prefix:, name:)
    end

    def mount_path(scope: nil)
      Karya::Internal::MountPath.build(DEFAULT_MOUNT_PATH, scope:)
    end

    def health_payload(backend_class: nil, backend_options: nil)
      support.load_config_file!
      backend_class ||= Karya.backend_class
      backend_options ||= Karya.backend_options
      Karya::FrameworkRuntime.shared_runtime(backend_class:, backend_options:).health_payload
    end

    def readiness_payload(backend_class: nil, backend_options: nil)
      support.load_config_file!
      backend_class ||= Karya.backend_class
      backend_options ||= Karya.backend_options
      Karya::FrameworkRuntime.shared_runtime(backend_class:, backend_options:).readiness_payload
    end

    def operator_payload(backend_class: nil, backend_options: nil, scope: nil)
      support.load_config_file!
      backend_class ||= Karya.backend_class
      backend_options ||= Karya.backend_options
      Karya::FrameworkRuntime.shared_runtime(backend_class:, backend_options:).operator_payload(mount_path: mount_path(scope:))
    end

    def runtime_probe_payload(backend_class: nil, backend_options: nil, scope: nil)
      support.load_config_file!
      backend_class ||= Karya.backend_class
      backend_options ||= Karya.backend_options
      Karya::FrameworkRuntime.shared_runtime(backend_class:, backend_options:).runtime_probe_payload(
        job_prefix: 'roda-probe',
        worker_id: 'roda-probe-worker',
        mount_path: mount_path(scope:)
      )
    end

    def configuration
      support.configuration
    end

    def load_config_file!(path: 'config/karya.yml')
      support.load_config_file!(path:)
    end

    def register_workflows(*sources)
      configuration.register_workflows(*sources)
    end

    def configure_operator_authorizer(authorizer = nil)
      support.configure_operator_authorizer(authorizer)
    end

    def operator_access_authorized?(request_context, authorizer: nil)
      support.operator_access_authorized?(request_context, authorizer:)
    end

    def operator_authorizer
      support.operator_authorizer
    end

    def framework_root_path
      support.framework_root_path
    end

    def runtime_inspect(queues:, name: nil)
      support.runtime_inspect(queues:, name:)
    end

    def runtime_drain(queues:, name: nil)
      support.runtime_drain(queues:, name:)
    end

    def runtime_force_stop(queues:, name: nil)
      support.runtime_force_stop(queues:, name:)
    end
  end
end

# :nocov:
Karya::Roda::RakeTasks.load! if defined?(Rake.application)
# :nocov:
