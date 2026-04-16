# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'thor'
require_relative 'base'
require_relative 'version'
require_relative 'worker'
require_relative 'worker_supervisor'
require_relative 'cli/config_builder'
require_relative 'cli/integer_option'
require_relative 'cli/env_prefix'
require_relative 'cli/handler_parser'
require_relative 'cli/mapping_entry'
require_relative 'cli/runtime_command'
require_relative 'cli/signal_subscription'

module Karya
  # The CLI class defines the command-line interface for the Karya gem. It uses Thor to handle command parsing and execution.
  class CLI < Thor
    package_name 'karya'
    default_task :help

    def self.exit_on_failure?
      true
    end

    def self.start(given_args = ARGV, config = {})
      puts header unless config[:suppress_header]
      super
    end

    def self.header
      art = <<~'TEXT'
         _  __     _     ____   __   __    _
        | |/ /    / \   |  _ \  \ \ / /   / \
        | ' /    / _ \  | |_) |  \ V /   / _ \
        | . \   / ___ \ |  _ <    | |   / ___ \
        |_|\_\ /_/   \_\|_| \_\   |_|  /_/   \_\
      TEXT

      "#{art}\n#{Karya::TAGLINE} · v#{Karya::VERSION}\n"
    end

    map %w[--help -h] => :help
    map %w[--version -v] => :version

    desc 'version', 'Print the current version'
    def version
      # version is printed in the header, so we can just exit here
      exit(0)
    end

    desc 'help [COMMAND]', 'Describe available commands or one specific command'
    def help(command = nil)
      super
    end

    desc 'worker QUEUE [QUEUE...]',
         'Start a worker supervisor for one or more queues (manages processes and per-process threads)'
    method_option :processes, type: :numeric
    method_option :threads, type: :numeric
    method_option :state_file, type: :string
    method_option :env_prefix, type: :string
    method_option :worker_id, type: :string, default: "worker-#{Process.pid}"
    method_option :lease_duration, type: :numeric, default: 30
    method_option :default_execution_timeout, type: :numeric
    method_option :poll_interval, type: :numeric, default: Karya::Worker::DEFAULT_POLL_INTERVAL
    method_option :handler, type: :array, default: []
    method_option :require, type: :array, default: []
    method_option :max_iterations, type: :numeric
    method_option :stop_when_idle, type: :boolean, default: false
    def worker(*queues)
      load_required_files(options.fetch(:require))
      supervisor = Karya::WorkerSupervisor.new(**build_worker_configuration(queues))

      status = supervisor.run
      exit(status) if status.positive?
    end

    desc 'runtime SUBCOMMAND ...ARGS', 'Inspect or control a running supervisor via the local runtime state file'
    subcommand 'runtime', RuntimeCommand

    no_commands do
      def build_worker_configuration(queues)
        ConfigBuilder.build(
          options:,
          queues:,
          queue_store: Karya.queue_store,
          defaults: {
            processes: Karya::WorkerSupervisor::DEFAULT_PROCESSES,
            threads: Karya::WorkerSupervisor::DEFAULT_THREADS
          },
          helpers: {
            coerce_optional_positive_integer_option: method(:coerce_optional_positive_integer_option),
            normalize_env_prefix_option: method(:normalize_env_prefix_option),
            resolve_positive_integer_option: method(:resolve_positive_integer_option)
          }
        )
      end

      def resolve_positive_integer_option(option_name, env_prefix:, defaults:)
        raw_value = options[option_name]
        raw_value ||= ENV.fetch("KARYA_#{env_prefix}_#{option_name.to_s.upcase}", nil) if env_prefix
        raw_value ||= defaults.fetch(option_name)
        IntegerOption.new(option_name, raw_value).normalize
      end

      def coerce_optional_positive_integer_option(option_name)
        options[option_name]&.then do |raw_value|
          IntegerOption.new(option_name, raw_value).normalize
        end
      end

      def load_required_files(paths)
        paths.each do |path|
          require File.expand_path(path)
        end
      end

      def normalize_env_prefix_option(option_name)
        options[option_name]&.then do |raw_value|
          EnvPrefix.new(raw_value).normalize
        end
      end
    end

    # Logger and instrumenter globals are process-wide defaults.
    # Pass explicit runtime collaborators when multiple isolated runtimes share a process.
    private_constant :ConfigBuilder, :EnvPrefix, :HandlerParser, :IntegerOption, :MappingEntry, :SignalSubscription
  end
end
