# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'open3'
require 'timeout'

module KaryaSpecSupport
  class E2ESubprocess
    class CleanupError < StandardError; end
    class OutputTimeout < Timeout::Error; end

    DEFAULT_TIMEOUT = 30
    TERMINATION_TIMEOUT = 2

    attr_reader :pid

    def self.capture(*command, timeout: DEFAULT_TIMEOUT, **options)
      deadline = monotonic_time + timeout
      cleanup_reserve = [TERMINATION_TIMEOUT, timeout / 2.0].min
      operation_deadline = deadline - cleanup_reserve
      process = new(*command, **options)
      begin
        status = process.wait(timeout: remaining_time(operation_deadline))
        process.wait_for_output(timeout: remaining_time(operation_deadline))
        result = [process.stdout, process.stderr, status]
      rescue Timeout::Error
        failure = Timeout::Error.new("subprocess timed out after #{timeout}s:\n#{process.output}")
      ensure
        begin
          process.close(deadline:)
        rescue CleanupError => error
          failure = failure ? CleanupError.new("#{failure.message}\n#{error.message}") : error
        end
      end

      raise failure if failure

      result
    end

    def self.close_preserving_failure(process, active_exception: $!)
      process&.close
    rescue CleanupError => error
      raise error unless active_exception

      warn "#{error.class}: #{error.message}"
    end

    def self.monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    private_class_method :monotonic_time

    def self.remaining_time(deadline)
      remaining = deadline - monotonic_time
      raise Timeout::Error unless remaining.positive?

      remaining
    end
    private_class_method :remaining_time

    def initialize(*command, **options)
      @stdin, @stdout_io, @stderr_io, @wait_thread = Open3.popen3(*command, **options.merge(pgroup: true))
      @pid = @wait_thread.pid
      @stdout = +''
      @stderr = +''
      @output_lock = Mutex.new
      @stdout_reader = read_output(@stdout_io, @stdout)
      @stderr_reader = read_output(@stderr_io, @stderr)
      @stdin.close
    end

    def alive?
      @wait_thread.alive?
    end

    def wait(timeout: DEFAULT_TIMEOUT)
      Timeout.timeout(timeout) { @wait_thread.value }
    end

    def wait_for_output(timeout: TERMINATION_TIMEOUT)
      Timeout.timeout(timeout, OutputTimeout) do
        @stdout_reader.value
        @stderr_reader.value
      end
    end

    def stdout
      output_snapshot(@stdout)
    end

    def stderr
      output_snapshot(@stderr)
    end

    def output
      [stdout, stderr].reject(&:empty?).join("\n")
    end

    def close(deadline: monotonic_time + TERMINATION_TIMEOUT)
      terminate_process_group(deadline) unless shutdown_complete?
      close_output_streams
      join_until(@wait_thread, deadline)
      join_until(@stdout_reader, deadline)
      join_until(@stderr_reader, deadline)
      wait_for_shutdown(deadline)
      verify_closed
    end

    private

    def read_output(stream, destination)
      Thread.new do
        loop do
          chunk = stream.readpartial(4096)
          @output_lock.synchronize { destination << chunk }
        end
      rescue EOFError, IOError
        nil
      end
    end

    def output_snapshot(buffer)
      @output_lock.synchronize { buffer.dup }
    end

    def output_readers_alive?
      @stdout_reader.alive? || @stderr_reader.alive?
    end

    def terminate_process_group(deadline)
      signal_process_group('TERM')
      grace_deadline = monotonic_time + (remaining_time(deadline) / 2.0)
      join_until(@wait_thread, grace_deadline)
      return if shutdown_complete?

      signal_process_group('KILL')
    end

    def signal_process_group(signal)
      Process.kill(signal, -pid)
    rescue Errno::ESRCH
      nil
    end

    def close_output_streams
      @stdout_io.close unless @stdout_io.closed?
      @stderr_io.close unless @stderr_io.closed?
    end

    def join_until(thread, deadline)
      thread.join([remaining_time(deadline), 0].max)
    end

    def verify_closed
      return if shutdown_complete?

      raise CleanupError, "subprocess cleanup incomplete for process group #{pid}:\n#{output}"
    end

    def wait_for_shutdown(deadline)
      until shutdown_complete?
        remaining = remaining_time(deadline)
        break unless remaining.positive?

        sleep([remaining, 0.01].min)
      end
    end

    def shutdown_complete?
      !alive? && !output_readers_alive? && !process_group_alive?
    end

    def process_group_alive?
      Process.kill(0, -pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def remaining_time(deadline)
      deadline - monotonic_time
    end
  end
end
