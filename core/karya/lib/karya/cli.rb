# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'thor'

module Karya
  # The CLI class defines the command-line interface for the Karya gem. It uses Thor to handle command parsing and execution.
  class CLI < Thor
    package_name 'karya'
    default_task :help

    def self.start(given_args = ARGV, config = {})
      puts header
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

    desc 'worker QUEUE [QUEUE...]', 'Start a worker for one or more queues'
    method_option :worker_id, type: :string, default: "worker-#{Process.pid}"
    method_option :lease_duration, type: :numeric, default: 30
    method_option :poll_interval, type: :numeric, default: Karya::Worker::DEFAULT_POLL_INTERVAL
    method_option :handler, type: :array, default: []
    method_option :require, type: :array, default: []
    method_option :max_iterations, type: :numeric
    method_option :stop_when_idle, type: :boolean, default: false
    def worker(*queues)
      load_required_files(options.fetch(:require))

      worker = Karya::Worker.new(
        queue_store: Karya.queue_store,
        worker_id: options.fetch(:worker_id),
        queues:,
        handlers: HandlerParser.parse(options.fetch(:handler)),
        lease_duration: options.fetch(:lease_duration)
      )

      worker.run(
        poll_interval: options.fetch(:poll_interval),
        max_iterations: options[:max_iterations],
        stop_when_idle: options.fetch(:stop_when_idle)
      )
    end

    no_commands do
      def load_required_files(paths)
        paths.each do |path|
          require File.expand_path(path)
        end
      end
    end

    # Parses explicit handler mapping entries passed through the CLI.
    class HandlerParser
      def self.parse(entries)
        new(entries).parse
      end

      def initialize(entries)
        @entries = entries
      end

      def parse
        entries.each_with_object({}) do |entry, handlers|
          MappingEntry.new(entry).merge_into(handlers)
        end
      end

      private

      attr_reader :entries
    end

    # Parses one CLI handler mapping in `NAME=CONSTANT` format.
    class MappingEntry
      def initialize(entry)
        @entry = entry
      end

      def name
        split_entry.fetch(0)
      end

      def constant_name
        split_entry.fetch(1)
      end

      def merge_into(handlers)
        handlers[name] = Karya::ConstantResolver.new(constant_name).resolve
      rescue Karya::ConstantResolutionError => e
        raise Thor::Error, e.message
      end

      private

      attr_reader :entry

      def split_entry
        @split_entry ||= begin
          name, constant_name = entry.to_s.split('=', 2)
          raise Thor::Error, "handler entries must use NAME=CONSTANT format: #{entry.inspect}" if name.to_s.strip.empty? || constant_name.to_s.strip.empty?

          [name.strip, constant_name.strip].freeze
        end
      end
    end

    private_constant :HandlerParser, :MappingEntry
  end
end
