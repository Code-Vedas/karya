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
      class_option :state_file, type: :string, required: true

      def self.exit_on_failure?
        true
      end

      desc 'show', 'Inspect a running supervisor from the runtime state file'
      map 'inspect' => :show
      def show
        payload = Karya::Internal::FrameworkRuntimeControl.inspect(state_file: runtime_control_state_file)
        puts JSON.pretty_generate(payload)
      rescue Karya::WorkerSupervisor::InvalidRuntimeStateFileError,
             Karya::WorkerSupervisor::RuntimeControlUnavailableError => e
        raise_runtime_control_error(e)
      end

      desc 'drain', 'Request graceful drain for the supervisor recorded in the runtime state file'
      def drain
        Karya::Internal::FrameworkRuntimeControl.drain(state_file: runtime_control_state_file)
      rescue Karya::WorkerSupervisor::InvalidRuntimeStateFileError,
             Karya::WorkerSupervisor::RuntimeControlUnavailableError => e
        raise_runtime_control_error(e)
      end

      desc 'force_stop', 'Force-stop the supervisor recorded in the runtime state file'
      map 'force-stop' => :force_stop
      def force_stop
        Karya::Internal::FrameworkRuntimeControl.force_stop(state_file: runtime_control_state_file)
      rescue Karya::WorkerSupervisor::InvalidRuntimeStateFileError,
             Karya::WorkerSupervisor::RuntimeControlUnavailableError => e
        raise_runtime_control_error(e)
      end

      private

      def runtime_control_state_file
        options.fetch(:state_file)
      end

      def raise_runtime_control_error(error)
        runtime_control_state_file
        message = error.message
        message = "runtime control failed: #{message}" unless error.is_a?(Karya::WorkerSupervisor::InvalidRuntimeStateFileError)
        raise Thor::Error, message
      end
    end
  end
end
