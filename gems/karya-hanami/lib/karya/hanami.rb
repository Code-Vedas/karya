# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'karya'
require 'karya/dashboard'
require 'hanami/cli'
require_relative 'hanami/version'
require_relative 'hanami/job'
require_relative 'hanami/cli/work'
require_relative 'hanami/cli/runtime'
require_relative 'hanami/cli/install'
require_relative 'hanami/workflow'

module Karya
  # The Karya::Hanami module serves as the main namespace for the Karya Hanami integration.
  module Hanami
    # :nocov:

    module_function

    DEFAULT_MOUNT_PATH = '/karya'

    def support
      @support ||= Karya::Internal::FrameworkSupport.new(
        framework_name: 'hanami',
        job_base: Job,
        root_path_resolver: -> { Dir.pwd },
        environment_name_resolver: lambda {
          hanami_env = ENV['HANAMI_ENV'].to_s.strip
          next hanami_env unless hanami_env.empty?
          next ::Hanami.env.to_s if defined?(::Hanami)

          Karya::Internal::Config::RuntimeContext.environment_name_from(ENV)
        }
      )
    end

    def build_host_runtime(backend_class: nil, backend_options: nil)
      support.load_config_file!
      backend_class ||= Karya.backend_class
      backend_options ||= Karya.backend_options
      Karya::FrameworkRuntime.build(backend_class:, backend_options:)
    end

    # :nocov:

    def with_host_runtime(backend_class: nil, backend_options: nil, &)
      support.load_config_file!
      backend_class ||= Karya.backend_class
      backend_options ||= Karya.backend_options
      Karya::FrameworkRuntime.with_started_runtime(backend_class:, backend_options:, &)
    end

    def mount_path(prefix: nil)
      Karya::Internal::MountPath.build(DEFAULT_MOUNT_PATH, scope: prefix)
    end

    def render_dashboard_page(prefix: nil, title: Karya::Dashboard::DEFAULT_TITLE, asset_prefix: nil, name: 'dashboard')
      Karya::Dashboard.render_document(title:, mount_path: mount_path(prefix:), asset_prefix:, name:)
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

    def operator_payload(backend_class: nil, backend_options: nil, prefix: nil)
      support.load_config_file!
      backend_class ||= Karya.backend_class
      backend_options ||= Karya.backend_options
      Karya::FrameworkRuntime.shared_runtime(backend_class:, backend_options:).operator_payload(mount_path: mount_path(prefix:))
    end

    def runtime_probe_payload(backend_class: nil, backend_options: nil, prefix: nil)
      support.load_config_file!
      backend_class ||= Karya.backend_class
      backend_options ||= Karya.backend_options
      Karya::FrameworkRuntime.shared_runtime(backend_class:, backend_options:).runtime_probe_payload(
        job_prefix: 'hanami-probe',
        worker_id: 'hanami-probe-worker',
        mount_path: mount_path(prefix:)
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

Hanami::CLI.register('karya:work', Karya::Hanami::CLI::Work)
Hanami::CLI.register('karya:runtime', Karya::Hanami::CLI::Runtime)
Hanami::CLI.register('karya:install', Karya::Hanami::CLI::Install)
