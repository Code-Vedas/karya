# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'json'
require 'socket'

module Karya
  module Internal
    # Shared runtime inspection and control helper for framework wrappers.
    module FrameworkRuntimeControl
      MAX_RESPONSE_BYTES = 5 * 1024 * 1024
      RESPONSE_TIMEOUT_SECONDS = 5

      module_function

      def inspect(state_file:)
        Karya::WorkerSupervisor::RuntimeStateStore.live_payload!(state_file)
      end

      def drain(state_file:)
        send_control_command(state_file:, command: 'drain')
      end

      def force_stop(state_file:)
        send_control_command(state_file:, command: 'force_stop')
      end

      def send_control_command(state_file:, command:)
        payload = Karya::WorkerSupervisor::RuntimeStateStore.control_payload!(state_file)
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
        return response if response.fetch('ok', false)

        raise Karya::WorkerSupervisor::RuntimeControlUnavailableError,
              response.fetch('error', 'unknown runtime control error')
      rescue Karya::WorkerSupervisor::InvalidRuntimeStateFileError,
             Errno::ENOENT,
             Errno::ECONNREFUSED,
             Errno::ENOTSOCK,
             Errno::EPIPE,
             Errno::EPERM,
             Errno::EINVAL,
             KeyError,
             JSON::ParserError => e
        raise Karya::WorkerSupervisor::RuntimeControlUnavailableError, e.message
      end
      module_function :send_control_command

      def read_response(socket)
        buffer = +''
        loop do
          wait_for_response(socket)
          chunk = socket.readpartial(1024)
          next if chunk.empty?

          if (buffer.bytesize + chunk.bytesize) > MAX_RESPONSE_BYTES
            raise Karya::WorkerSupervisor::RuntimeControlUnavailableError,
                  "supervisor response exceeded #{MAX_RESPONSE_BYTES} bytes"
          end

          buffer << chunk
        end
      rescue EOFError
        buffer
      end
      module_function :read_response

      def wait_for_response(socket)
        return if socket.wait_readable(RESPONSE_TIMEOUT_SECONDS)

        raise Karya::WorkerSupervisor::RuntimeControlUnavailableError,
              "timed out waiting for supervisor response after #{RESPONSE_TIMEOUT_SECONDS} seconds"
      end
      module_function :wait_for_response
    end
  end
end
