# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'open3'
require 'timeout'

class E2ESubprocess
  DEFAULT_TIMEOUT = 30
  TERMINATION_TIMEOUT = 2

  attr_reader :pid

  def self.capture(*command, timeout: DEFAULT_TIMEOUT, **options)
    process = new(*command, **options)
    status = process.wait(timeout:)
    process.wait_for_output(timeout: TERMINATION_TIMEOUT)
    [process.stdout, process.stderr, status]
  rescue Timeout::Error
    raise Timeout::Error, "subprocess timed out after #{timeout}s:\n#{process&.output}"
  ensure
    process&.close
  end

  def initialize(*command, **options)
    @stdin, @stdout_io, @stderr_io, @wait_thread = Open3.popen3(*command, **options, pgroup: true)
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
    Timeout.timeout(timeout) do
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

  def close
    terminate_process_group if alive? || output_readers_alive?
    close_output_streams
    reap_process
    reap_output_readers
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

  def terminate_process_group
    signal_process_group('TERM')
    @wait_thread.join(TERMINATION_TIMEOUT)
    return unless alive? || output_readers_alive?

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

  def reap_process
    @wait_thread.join(TERMINATION_TIMEOUT)
  end

  def reap_output_readers
    @stdout_reader.join(TERMINATION_TIMEOUT)
    @stderr_reader.join(TERMINATION_TIMEOUT)
  end
end
