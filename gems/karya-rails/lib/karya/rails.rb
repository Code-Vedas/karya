# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'rails'
require 'action_controller/railtie'
require 'karya'
require 'karya/dashboard'

require_relative 'rails/version'
require_relative 'rails/engine'
require_relative 'rails/job'
require_relative 'rails/rake_tasks'
require_relative 'rails/workflow'

module Karya
  # Karya::Rails module serves as the main namespace for all Rails-specific integrations and functionalities related to the Karya gem.
  module Rails
    module_function

    DEFAULT_MOUNT_PATH = '/karya'

    def support
      @support ||= Karya::Internal::FrameworkSupport.new(
        framework_name: 'rails',
        job_base: Job,
        root_path_resolver: -> { ::Rails.root.to_s },
        environment_name_resolver: -> { ::Rails.env.to_s }
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

    def render_dashboard_page(
      scope: nil,
      mount_path: DEFAULT_MOUNT_PATH,
      title: Karya::Dashboard::DEFAULT_TITLE,
      asset_prefix: nil,
      name: 'dashboard'
    )
      if scope
        raise ArgumentError, 'scope and mount_path cannot be combined' unless mount_path == DEFAULT_MOUNT_PATH

        mount_path = Karya::Internal::MountPath.build(DEFAULT_MOUNT_PATH, scope:)
      end
      Karya::Dashboard.render_document(title:, mount_path:, asset_prefix:, name:)
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

    def operator_payload(backend_class: nil, backend_options: nil, mount_path: DEFAULT_MOUNT_PATH)
      support.load_config_file!
      backend_class ||= Karya.backend_class
      backend_options ||= Karya.backend_options
      Karya::FrameworkRuntime.shared_runtime(backend_class:, backend_options:).operator_payload(mount_path:)
    end

    def runtime_probe_payload(backend_class: nil, backend_options: nil, mount_path: DEFAULT_MOUNT_PATH)
      support.load_config_file!
      backend_class ||= Karya.backend_class
      backend_options ||= Karya.backend_options
      Karya::FrameworkRuntime.shared_runtime(backend_class:, backend_options:).runtime_probe_payload(
        job_prefix: 'rails-probe',
        worker_id: 'rails-probe-worker',
        mount_path:
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

    def active_job_queue_adapter
      Karya::ActiveJob.queue_adapter
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

    def active_job_handler = Karya::ActiveJob.handler

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
