# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'json'
require 'socket'
require 'fileutils'

module Karya
  class WorkerSupervisor
    # Supervisor-owned local socket server for runtime control commands.
    class RuntimeControlServer
      CLIENT_READ_TIMEOUT_SECONDS = 1
      MAX_REQUEST_BYTES = 4096
      STOP_TIMEOUT_SECONDS = 2
      HANDLED_RUNTIME_ERRORS = [RuntimeControlUnavailableError, InvalidRuntimeStateFileError].freeze
      INVALID_REQUEST_ERRORS = [KeyError, JSON::ParserError, TypeError].freeze

      # Maps a handled request error into the control protocol payload.
      class ErrorResponse
        def initialize(error:)
          @error = error
        end

        def to_h
          return invalid_request_payload if invalid_request_error?
          return runtime_error_payload if handled_runtime_error?

          raise error
        end

        private

        attr_reader :error

        def invalid_request_error?
          INVALID_REQUEST_ERRORS.any? { |klass| error.is_a?(klass) }
        end

        def handled_runtime_error?
          HANDLED_RUNTIME_ERRORS.any? { |klass| error.is_a?(klass) }
        end

        def invalid_request_payload
          { 'error' => "invalid control request: #{error.message}" }
        end

        def runtime_error_payload
          { 'error' => error.message }
        end
      end

      # Handles a single runtime control request/response exchange.
      class ClientSession
        READ_CHUNK_BYTES = 1024

        def initialize(client:, response_builder:)
          @client = client
          @response_builder = response_builder
        end

        def call
          client.write(JSON.generate(response_builder.call(read_request)))
        end

        private

        attr_reader :client, :response_builder

        def read_request
          buffer = +''
          loop do
            wait_for_client_readability
            buffer << client.readpartial(READ_CHUNK_BYTES)
            validate_request_size(buffer)
          end
        rescue EOFError
          buffer
        end

        def wait_for_client_readability
          return if client.wait_readable(CLIENT_READ_TIMEOUT_SECONDS)

          raise InvalidRuntimeStateFileError, 'runtime control request timed out while reading from client'
        end

        def validate_request_size(buffer)
          return if buffer.bytesize <= MAX_REQUEST_BYTES

          raise InvalidRuntimeStateFileError, "runtime control request exceeds #{MAX_REQUEST_BYTES} bytes"
        end
      end

      def initialize(path:, instance_token:, command_handler:, logger:)
        @path = path
        @instance_token = instance_token
        @command_handler = command_handler
        @logger = logger
        @server = nil
        @server_thread = nil
        @stopping = false
      end

      def start
        FileUtils.mkdir_p(File.dirname(path))
        unlink_stale_socket
        @server = UNIXServer.new(path)
        @stopping = false
        @server_thread = Thread.new { run_loop }
        self
      end

      def stop
        @stopping = true
        @server&.close
        stop_server_thread
      ensure
        FileUtils.rm_f(path) if File.socket?(path)
      end

      private

      attr_reader :command_handler, :instance_token, :logger, :path

      def unlink_stale_socket
        return unless File.exist?(path)
        return FileUtils.rm_f(path) if File.socket?(path)

        raise InvalidWorkerSupervisorConfigurationError,
              "runtime control socket path is already occupied by a non-socket file: #{path}"
      end

      def stop_server_thread
        return unless @server_thread

        return if @server_thread.join(STOP_TIMEOUT_SECONDS)

        @server_thread.kill
        @server_thread.join
      end

      def run_loop
        loop do
          client = nil
          client = @server.accept
          handle_client(client)
        rescue IOError, Errno::EBADF
          break if @stopping

          raise
        rescue StandardError => e
          logger.error('runtime control server failed', error_class: e.class.name, error_message: e.message, socket_path: path)
        ensure
          client&.close
        end
      end

      def handle_client(client)
        ClientSession.new(client:, response_builder: method(:control_response_for)).call
      end

      def control_response_for(raw_request)
        request = JSON.parse(raw_request)
        validate_request_shape(request)
        validate_instance_token(request)
        command = request.fetch('command')
        return { 'ok' => true } if command == 'ping'

        command_handler.call(command)
        { 'ok' => true }
      rescue StandardError => e
        ErrorResponse.new(error: e).to_h
      end

      def validate_instance_token(request)
        return if request.fetch('instance_token') == instance_token

        raise InvalidRuntimeStateFileError, 'runtime control token does not match the running supervisor'
      end

      def validate_request_shape(request)
        return if request.is_a?(Hash)

        raise TypeError, 'runtime control request must be a JSON object'
      end
    end
  end
end
