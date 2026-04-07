# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'json'
require 'socket'

module Karya
  class CLI < Thor
    # Runtime inspection and control commands backed by the local state file.
    class RuntimeCommand < Thor
      RESPONSE_TIMEOUT_SECONDS = 5

      class_option :state_file, type: :string, required: true

      def self.exit_on_failure?
        true
      end

      desc 'show', 'Inspect a running supervisor from the runtime state file'
      map 'inspect' => :show
      def show
        payload = Karya::WorkerSupervisor::RuntimeStateStore.live_payload!(options.fetch(:state_file))
        puts JSON.pretty_generate(payload)
      rescue Karya::WorkerSupervisor::InvalidRuntimeStateFileError => e
        raise Thor::Error, e.message
      end

      desc 'drain', 'Request graceful drain for the supervisor recorded in the runtime state file'
      def drain
        send_control_command('drain')
      end

      desc 'force_stop', 'Force-stop the supervisor recorded in the runtime state file'
      map 'force-stop' => :force_stop
      def force_stop
        send_control_command('force_stop')
      end

      private

      def send_control_command(command)
        payload = Karya::WorkerSupervisor::RuntimeStateStore.control_payload!(options.fetch(:state_file))
        response = UNIXSocket.open(payload.fetch('control_socket_path')) do |socket|
          socket.write(
            JSON.generate(
              'command' => command,
              'instance_token' => payload.fetch('instance_token')
            )
          )
          socket.close_write
          JSON.parse(read_response(socket))
        end
        return if response.fetch('ok', false)

        raise Thor::Error, response.fetch('error', 'unknown runtime control error')
      rescue Karya::WorkerSupervisor::InvalidRuntimeStateFileError,
             Errno::ENOENT,
             Errno::ECONNREFUSED,
             Errno::ENOTSOCK,
             Errno::EPIPE,
             Errno::EPERM,
             Errno::EINVAL,
             KeyError,
             JSON::ParserError => e
        message = e.message
        error_message = if e.is_a?(Karya::WorkerSupervisor::InvalidRuntimeStateFileError)
                          message
                        else
                          "runtime control failed: #{message}"
                        end
        raise Thor::Error, error_message
      end

      def read_response(socket)
        buffer = +''
        loop do
          wait_for_response(socket)
          buffer << socket.readpartial(1024)
        end
      rescue EOFError
        buffer
      end

      def wait_for_response(socket)
        return if socket.wait_readable(RESPONSE_TIMEOUT_SECONDS)

        raise Thor::Error, "runtime control failed: timed out waiting for supervisor response after #{RESPONSE_TIMEOUT_SECONDS} seconds"
      end
    end
  end
end
