# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'json'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'securerandom'
require 'timeout'
require 'tmpdir'

module FrameworkRuntimeControlE2ESupport
  def framework_runtime_control_env(framework:, framework_gem_root:, database_url:, namespace:, worker_name:, worker: false)
    kaal_database_url = database_url.sub(/\Asqlite3:\/\//, 'sqlite://')
    env = {
      'KARYA_RUNTIME_CONTROL_E2E_DATABASE_URL' => database_url,
      'KARYA_RUNTIME_CONTROL_E2E_NAMESPACE' => namespace,
      'KARYA_FRAMEWORK_E2E_BACKEND' => 'sqlite',
      'KARYA_FRAMEWORK_E2E_DATABASE_URL' => database_url,
      'KARYA_FRAMEWORK_E2E_NAMESPACE' => namespace,
      'KARYA_FRAMEWORK_E2E_KAAL_BACKEND' => 'sqlite',
      'KARYA_FRAMEWORK_E2E_KAAL_DATABASE_URL' => kaal_database_url,
      'KARYA_FRAMEWORK_E2E_KAAL_NAMESPACE' => namespace,
      'NO_COVERAGE' => '1'
    }

    case framework
    when :rails
      env['RAILS_ENV'] = 'test'
    when :hanami
      env['HANAMI_ENV'] = 'test'
      env['BUNDLE_GEMFILE'] = File.join(framework_gem_root, 'Gemfile')
    when :roda, :sinatra
      env['RACK_ENV'] = 'test'
      env['BUNDLE_GEMFILE'] = File.join(framework_gem_root, 'Gemfile')
      env['KARYA_WORKER_NAME'] = worker_name
    else
      raise ArgumentError, "unsupported framework #{framework.inspect}"
    end

    return env unless worker && %i[roda sinatra].include?(framework)

    env.merge(
      'KARYA_LEASE_DURATION' => '60',
      'KARYA_PROCESSES' => '1',
      'KARYA_THREADS' => '1',
      'KARYA_POLL_INTERVAL' => '0'
    )
  end

  def framework_worker_command(framework:, queue:, worker_name:)
    case framework
    when :rails
      [
        File.join(current_app_root, 'bin', 'rails'),
        'karya:work',
        "--name=#{worker_name}",
        '--processes=1',
        '--threads=1',
        '--lease-duration=60',
        '--poll-interval=0',
        queue
      ]
    when :hanami
      [
        'bundle', 'exec', RbConfig.ruby, '-e',
        <<~RUBY
          require 'karya/hanami'
          handler = Class.new do
            def self.call(*)
            end
          end
          Karya::Hanami.support.run_worker(
            queues: [#{queue.inspect}],
            name: #{worker_name.inspect},
            extra_handlers: { 'runtime_control_e2e_ping' => handler },
            processes: 1,
            threads: 1,
            poll_interval: 0,
            lease_duration: 60
          )
        RUBY
      ]
    when :roda, :sinatra
      framework_module = framework == :roda ? 'Karya::Roda' : 'Karya::Sinatra'
      [
        'bundle', 'exec', RbConfig.ruby, '-e',
        <<~RUBY
          require_relative 'app'
          handler = Class.new do
            def self.call(*)
            end
          end
          #{framework_module}.support.run_worker(
            queues: [#{queue.inspect}],
            extra_handlers: { 'runtime_control_e2e_ping' => handler },
            processes: 1,
            threads: 1,
            poll_interval: 0,
            lease_duration: 60,
            name: #{worker_name.inspect}
          )
        RUBY
      ]
    else
      raise ArgumentError, "unsupported framework #{framework.inspect}"
    end
  end

  def framework_runtime_command(framework:, action:, queue:, worker_name:)
    case framework
    when :rails
      [
        File.join(current_app_root, 'bin', 'rails'),
        "karya:runtime:#{runtime_task_name(action)}",
        "--name=#{worker_name}",
        queue
      ]
    when :hanami
      [
        'bundle', 'exec', RbConfig.ruby, '-e',
        <<~RUBY
          require 'karya/hanami'
          Karya::Hanami::CLI::Runtime.new.call(
            action: #{runtime_action_name(action).inspect},
            queues: #{queue.inspect},
            name: #{worker_name.inspect}
          )
        RUBY
      ]
    when :roda, :sinatra
      ['bundle', 'exec', 'rake', "karya:runtime:#{runtime_task_name(action)}[#{queue}]"]
    else
      raise ArgumentError, "unsupported framework #{framework.inspect}"
    end
  end

  def runtime_action_name(action)
    action == :force_stop ? 'force-stop' : action.to_s
  end
  private :runtime_action_name

  def runtime_task_name(action)
    action == :force_stop ? 'force_stop' : action.to_s
  end
  private :runtime_task_name

  def framework_runtime_state_file(queue:, worker_name:)
    Karya::Internal::FrameworkRuntimeIdentity.state_file(
      root_path: current_app_root,
      queues: [queue],
      name: worker_name
    )
  end

  def wait_for_framework_runtime_phase(state_file, *phases)
    expected_phases = phases.flatten
    wait_until do
      snapshot = JSON.parse(File.read(state_file)).fetch('snapshot')
      expected_phases.include?(snapshot.fetch('phase')) ? snapshot : nil
    end
  end

  def wait_for_framework_runtime_start(state_file, wait_thr, stdout_and_stderr)
    wait_until do
      if wait_thr.join(0)
        output = stdout_and_stderr.read
        raise "worker exited before runtime control started:\n#{output}"
      end

      next unless File.exist?(state_file)

      payload = JSON.parse(File.read(state_file))
      snapshot = payload.fetch('snapshot')
      control_socket_path = payload['control_socket_path']
      next unless %w[starting running draining force_stopping].include?(snapshot.fetch('phase'))
      next unless control_socket_path && File.socket?(control_socket_path)

      payload
    rescue Errno::ENOENT, JSON::ParserError, KeyError
      next
    end
  end

  def parse_framework_runtime_json(output)
    json_start = output.index('{')
    raise "runtime command did not emit JSON:\n#{output}" unless json_start

    JSON.parse(output.slice(json_start..))
  end

  def wait_until(timeout: 10)
    Timeout.timeout(timeout) do
      loop do
        result = yield
        return result if result

        sleep(0.05)
      end
    end
  end

  def cleanup_framework_worker_process(wait_thr)
    return unless wait_thr.alive?

    Process.kill('TERM', wait_thr.pid)
    Timeout.timeout(2) do
      wait_thr.join
    end
    Process.kill('KILL', wait_thr.pid) if wait_thr.alive?
  rescue Timeout::Error
    Process.kill('KILL', wait_thr.pid) if wait_thr.alive?
  rescue Errno::ESRCH
    nil
  end

  def request_framework_force_stop(supervisor_pid:, draining_marker_path:)
    Process.kill('TERM', supervisor_pid)
    wait_until { File.exist?(draining_marker_path) }
    Process.kill('TERM', supervisor_pid)
  rescue Errno::ESRCH
    nil
  end

  def write_stale_runtime_state_file!(live_state_file:, stale_state_file:)
    payload = JSON.parse(File.read(live_state_file))
    payload['instance_token'] = "stale-#{SecureRandom.hex(6)}"
    FileUtils.mkdir_p(File.dirname(stale_state_file))
    File.write(stale_state_file, JSON.generate(payload))
  end

  def with_runtime_control_app_fixture(app_root:, framework:)
    queue = 'billing'
    worker_name = 'billing'
    rakefile = File.join(app_root, 'Rakefile')
    job_file = File.join(app_root, 'app', 'jobs', 'runtime_control_e2e_ping_job.rb')
    original_rakefile_source = File.exist?(rakefile) ? File.read(rakefile) : nil

    FileUtils.mkdir_p(File.dirname(job_file))
    File.write(job_file, runtime_control_job_source(framework:, queue:))

    if %i[roda sinatra].include?(framework)
      File.write(rakefile, runtime_control_rakefile_source(framework:))
    end

    yield(queue, worker_name)
  ensure
    File.delete(job_file) if job_file && File.exist?(job_file)

    if original_rakefile_source
      File.write(rakefile, original_rakefile_source)
    elsif rakefile && File.exist?(rakefile)
      File.delete(rakefile)
    end
  end

  def runtime_control_job_source(framework:, queue:)
    job_base = case framework
               when :rails then 'Karya::Rails::Job'
               when :hanami then 'Karya::Hanami::Job'
               when :roda then 'Karya::Roda::Job'
               when :sinatra then 'Karya::Sinatra::Job'
               else
                 raise ArgumentError, "unsupported framework #{framework.inspect}"
               end

    <<~RUBY
      # frozen_string_literal: true

      class RuntimeControlE2ePingJob < #{job_base}
        queue_as #{queue.inspect}
        karya_handler 'runtime_control_e2e_ping'

        def perform(*)
        end
      end
    RUBY
  end
  private :runtime_control_job_source

  def runtime_control_rakefile_source(framework:)
    framework_module = framework == :roda ? 'Karya::Roda' : 'Karya::Sinatra'

    <<~RUBY
      # frozen_string_literal: true

      require_relative 'app'
      #{framework_module}::RakeTasks.load!
    RUBY
  end
  private :runtime_control_rakefile_source
end

RSpec.configure do |config|
  config.include FrameworkRuntimeControlE2ESupport
end

RSpec.shared_examples 'framework runtime control e2e' do |framework:, framework_gem_root:|
  it 'inspects, drains, and force-stops a live worker through the framework runtime command' do
    database_url = Karya.backend_options.fetch(:url)
    namespace = Karya.backend_options.fetch(:namespace)

    with_runtime_control_app_fixture(app_root: current_app_root, framework:) do |queue, worker_name|
      state_file = framework_runtime_state_file(queue:, worker_name:)
      File.delete(state_file) if File.exist?(state_file)
      command_env = framework_runtime_control_env(
        framework:,
        framework_gem_root:,
        database_url:,
        namespace:,
          worker_name:,
          worker: true
      )

      Open3.popen2e(
        command_env,
        *framework_worker_command(framework:, queue:, worker_name:),
        chdir: current_app_root
      ) do |_stdin, stdout_and_stderr, wait_thr|
        begin
          wait_for_framework_runtime_start(state_file, wait_thr, stdout_and_stderr)

          inspect_stdout, inspect_stderr, inspect_status = Open3.capture3(
            framework_runtime_control_env(
              framework:,
              framework_gem_root:,
              database_url:,
              namespace:,
              worker_name:
            ),
            *framework_runtime_command(framework:, action: :inspect, queue:, worker_name:),
            chdir: current_app_root
          )
          inspect_payload = parse_framework_runtime_json(inspect_stdout)

          expect(inspect_status.exitstatus).to eq(0), -> { "stderr:\n#{inspect_stderr}" }
          expect(inspect_payload.fetch('snapshot').fetch('phase')).to match(/\A(?:starting|running|draining)\z/)

          drain_stdout, drain_stderr, drain_status = Open3.capture3(
            framework_runtime_control_env(
              framework:,
              framework_gem_root:,
              database_url:,
              namespace:,
              worker_name:
            ),
            *framework_runtime_command(framework:, action: :drain, queue:, worker_name:),
            chdir: current_app_root
          )

          expect(drain_status.exitstatus).to eq(0), -> { "stdout:\n#{drain_stdout}\n\nstderr:\n#{drain_stderr}" }
          expect(wait_for_framework_runtime_phase(state_file, 'draining')).to include('phase' => 'draining')

          force_stop_stdout, force_stop_stderr, force_stop_status = Open3.capture3(
            framework_runtime_control_env(
              framework:,
              framework_gem_root:,
              database_url:,
              namespace:,
              worker_name:
            ),
            *framework_runtime_command(framework:, action: :force_stop, queue:, worker_name:),
            chdir: current_app_root
          )

          expect(force_stop_status.exitstatus).to eq(0), -> { "stdout:\n#{force_stop_stdout}\n\nstderr:\n#{force_stop_stderr}" }
          runtime_phase = wait_for_framework_runtime_phase(state_file, 'force_stopping', 'stopped').fetch('phase')
          expect(runtime_phase).to match(/\A(?:force_stopping|stopped)\z/)
        rescue Timeout::Error
          output = wait_thr.join(0) ? stdout_and_stderr.read : '(worker still running)'
          state_payload = File.exist?(state_file) ? File.read(state_file) : '(missing state file)'
          raise "worker runtime control timed out:\nstate:\n#{state_payload}\n\noutput:\n#{output}"
        ensure
          cleanup_framework_worker_process(wait_thr)
        end
      end
    end
  end

  it 'fails with a runtime-control error when the framework state token is stale' do
    database_url = Karya.backend_options.fetch(:url)
    namespace = Karya.backend_options.fetch(:namespace)

    with_runtime_control_app_fixture(app_root: current_app_root, framework:) do |queue, worker_name|
      state_file = framework_runtime_state_file(queue:, worker_name:)
      File.delete(state_file) if File.exist?(state_file)
      stale_worker_name = "#{worker_name}-stale"
      stale_state_file = framework_runtime_state_file(queue:, worker_name: stale_worker_name)
      File.delete(stale_state_file) if File.exist?(stale_state_file)
      worker_env = framework_runtime_control_env(
        framework:,
        framework_gem_root:,
        database_url:,
        namespace:,
          worker_name:,
          worker: true
      )

      Open3.popen2e(
        worker_env,
        *framework_worker_command(framework:, queue:, worker_name:),
        chdir: current_app_root
      ) do |_stdin, stdout_and_stderr, wait_thr|
        begin
          wait_for_framework_runtime_start(state_file, wait_thr, stdout_and_stderr)
          write_stale_runtime_state_file!(live_state_file: state_file, stale_state_file:)

          command_stdout, command_stderr, command_status = Open3.capture3(
            framework_runtime_control_env(
              framework:,
              framework_gem_root:,
              database_url:,
              namespace:,
              worker_name: stale_worker_name
            ),
            *framework_runtime_command(framework:, action: :drain, queue:, worker_name: stale_worker_name),
            chdir: current_app_root
          )

          combined_output = "#{command_stdout}\n#{command_stderr}"
          expect(command_status.exitstatus).not_to eq(0), lambda {
            stale_state_payload = File.exist?(stale_state_file) ? File.read(stale_state_file) : '(missing state file)'
            <<~TEXT
              expected stale-token runtime command to fail
              stdout:
              #{command_stdout}

              stderr:
              #{command_stderr}

              state:
              #{stale_state_payload}
            TEXT
          }
          expect(combined_output).to include('runtime control token does not match the running supervisor')
        rescue Timeout::Error
          output = wait_thr.join(0) ? stdout_and_stderr.read : '(worker still running)'
          state_payload = File.exist?(state_file) ? File.read(state_file) : '(missing state file)'
          raise "worker runtime control timed out:\nstate:\n#{state_payload}\n\noutput:\n#{output}"
        ensure
          File.delete(stale_state_file) if File.exist?(stale_state_file)
          cleanup_framework_worker_process(wait_thr)
        end
      end
    end
  end
end
