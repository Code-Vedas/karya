# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../spec_helper'

RSpec.describe Karya::CLI, :e2e, :integration do
  def run_cli(*args)
    Open3.capture3(*karya_command(*args), chdir: KaryaE2EHelpers::PACKAGE_ROOT)
  end

  it 'executes a queued job end-to-end through exe/karya worker' do
    Dir.mktmpdir('karya-cli-e2e') do |directory|
      state_file = File.join(directory, 'runtime.json')
      marker_file = File.join(directory, 'handler.json')
      boot_file = write_boot_file(
        directory:,
        handler_class_name: 'CliWorkerSuccessHandler',
        marker_path: marker_file,
        handler_body: <<~RUBY.strip
          File.write(marker_path, JSON.generate('account_id' => account_id, 'pid' => Process.pid))
        RUBY
      )

      stdout, stderr, status = run_cli(
        'worker',
        'billing',
        '--require',
        boot_file,
        '--handler',
        'billing_sync=CliWorkerSuccessHandler',
        '--worker-id',
        'worker-cli-e2e',
        '--processes',
        '1',
        '--threads',
        '1',
        '--poll-interval',
        '0',
        '--max-iterations',
        '1',
        '--state-file',
        state_file
      )

      expect(status.exitstatus).to eq(0), -> { "stdout:\n#{stdout}\n\nstderr:\n#{stderr}" }
      expect(JSON.parse(File.read(marker_file))).to include('account_id' => 42)

      runtime_state = read_runtime_state(state_file)
      expect(runtime_state.fetch('snapshot').fetch('phase')).to eq('stopped')
      expect(runtime_state.fetch('snapshot').fetch('child_processes')).not_to be_empty
    end
  end

  it 'exits non-zero when the supervisor is force-stopped by repeated TERM signals' do
    Dir.mktmpdir('karya-cli-force-stop') do |directory|
      state_file = File.join(directory, 'runtime.json')
      marker_file = File.join(directory, 'started.txt')
      boot_file = write_boot_file(
        directory:,
        handler_class_name: 'CliWorkerBlockingHandler',
        marker_path: marker_file,
        handler_body: <<~RUBY.strip
          File.write(marker_path, Process.pid.to_s)
          loop { sleep 0.1 }
        RUBY
      )

      Open3.popen2e(*karya_command(
        'worker',
        'billing',
        '--require',
        boot_file,
        '--handler',
        'billing_sync=CliWorkerBlockingHandler',
        '--worker-id',
        'worker-cli-force-stop',
        '--processes',
        '1',
        '--threads',
        '1',
        '--poll-interval',
        '0',
        '--state-file',
        state_file
      ), chdir: KaryaE2EHelpers::PACKAGE_ROOT) do |_stdin, stdout_and_stderr, wait_thr|
        process_status = nil

        begin
          wait_until { File.exist?(marker_file) && File.exist?(state_file) }
          supervisor_pid = read_runtime_state(state_file).fetch('supervisor_pid')
          Process.kill('TERM', supervisor_pid)
          sleep(0.1)
          Process.kill('TERM', supervisor_pid)
        rescue Errno::ESRCH
          nil
        ensure
          begin
            if wait_thr.alive?
              Process.kill('TERM', wait_thr.pid)
              sleep(0.1)
              Process.kill('KILL', wait_thr.pid) if wait_thr.alive?
            end
          rescue Errno::ESRCH
            nil
          ensure
            process_status ||= Timeout.timeout(10) { wait_thr.value }
            output = stdout_and_stderr.read

            expect(process_status.exitstatus).to eq(1), -> { "worker output:\n#{output}" }
            expect(File.read(marker_file).strip).not_to be_empty
            expect(read_runtime_state(state_file).fetch('snapshot').fetch('phase')).to eq('stopped')
          end
        end
      end
    end
  end
end
