# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'json'
require 'tmpdir'
require 'tempfile'
require 'fileutils'
require 'time'
require 'securerandom'
require 'digest'
require 'socket'

module Karya
  class WorkerSupervisor
    # Raised when runtime control cannot be performed on the current supervisor.
    class RuntimeControlUnavailableError < Error; end

    # Raised when the runtime state file is missing or invalid.
    class InvalidRuntimeStateFileError < Error; end

    # File-backed runtime state store shared across the supervisor and child processes.
    # :reek:MissingSafeMethod { exclude: [validate_control_socket_path!, prevent_live_supervisor_takeover!] }
    # rubocop:disable Metrics/ClassLength
    class RuntimeStateStore
      LOCK_RETRY_INTERVAL = 0.01
      LOCK_TIMEOUT_SECONDS = 1
      CONTROL_SOCKET_TIMEOUT_SECONDS = 1
      MAX_UNIX_SOCKET_PATH_BYTES = 103
      SCHEMA_VERSION = 1
      RUNNING_PHASE = 'running'
      DRAINING_PHASE = 'draining'
      FORCE_STOPPING_PHASE = 'force_stopping'
      STOPPED_PHASE = 'stopped'
      CHILD_RUNNING_STATE = 'running'
      CHILD_DRAINING_STATE = 'draining'
      CHILD_FORCE_STOPPING_STATE = 'force_stopping'
      CHILD_STOPPED_STATE = 'stopped'
      THREAD_BOOTING_STATE = 'booting'
      THREAD_POLLING_STATE = 'polling'
      THREAD_RUNNING_STATE = 'running'
      THREAD_IDLE_STATE = 'idle'
      THREAD_STOPPING_STATE = 'stopping'
      THREAD_STOPPED_STATE = 'stopped'
      SNAPSHOT_PHASES = [RUNNING_PHASE, DRAINING_PHASE, FORCE_STOPPING_PHASE, STOPPED_PHASE].freeze
      CHILD_STATES = [CHILD_RUNNING_STATE, CHILD_DRAINING_STATE, CHILD_FORCE_STOPPING_STATE, CHILD_STOPPED_STATE].freeze
      THREAD_STATES = [
        THREAD_BOOTING_STATE,
        THREAD_POLLING_STATE,
        THREAD_RUNNING_STATE,
        THREAD_IDLE_STATE,
        THREAD_STOPPING_STATE,
        THREAD_STOPPED_STATE
      ].freeze

      # No-op runtime state store used by isolated unit tests and local-only runners.
      class NullStore
        attr_reader :snapshot

        def initialize
          @snapshot = RuntimeSnapshot.new(
            worker_id: 'worker-supervisor',
            supervisor_pid: Process.pid,
            queues: [],
            configured_processes: 0,
            configured_threads: 0,
            phase: STOPPED_PHASE,
            child_processes: []
          )
        end

        def write_running; end
        alias write_running! write_running

        def mark_supervisor_phase(_phase); end
        def register_child(_pid); end
        def mark_child_phase(_pid, _phase); end
        def mark_child_stopped(_pid); end
        def register_thread(**); end
        def mark_thread_state(**); end
        def write_stopped; end
        alias write_stopped! write_stopped
      end

      # Encapsulates mutation of the JSON runtime payload.
      class MutablePayload
        # Encapsulates thread-list mutation for a single child-process payload.
        class ChildPayload
          def initialize(child)
            @child = child
            @threads = child.fetch('threads')
          end

          def register_thread(worker_id:, thread_index:)
            @child['thread_count'] = [@child['thread_count'], thread_index].max
            thread = find_or_build_thread(worker_id:, thread_index:)
            thread['state'] ||= THREAD_BOOTING_STATE
          end

          def mark_thread_state(worker_id:, state:, thread_index:)
            @child['thread_count'] = [@child['thread_count'], thread_index].max
            find_or_build_thread(worker_id:, thread_index:)['state'] = state
          end

          private

          def find_or_build_thread(worker_id:, thread_index:)
            @threads.find { |entry| entry['worker_id'] == worker_id } || begin
              thread = {
                'worker_id' => worker_id,
                'state' => THREAD_BOOTING_STATE,
                'thread_index' => thread_index
              }
              @threads << thread
              @threads.sort_by! { |entry| entry['thread_index'] }
              thread
            end
          end
        end

        def initialize(payload:, configuration:)
          @payload = payload
          @configuration = configuration
          @snapshot = payload.fetch('snapshot')
        end

        def mark_running(supervisor_pid, started_at:, instance_token:, control_socket_path:)
          @payload['started_at'] = started_at
          @payload['instance_token'] = instance_token
          @payload['control_socket_path'] = control_socket_path
          @payload['supervisor_pid'] = supervisor_pid
          @snapshot['supervisor_pid'] = supervisor_pid
          @snapshot['phase'] = RUNNING_PHASE
          self
        end

        def mark_supervisor_phase(phase)
          return self if @snapshot['phase'] == STOPPED_PHASE

          @snapshot['phase'] = phase
          self
        end

        def register_child(pid)
          child = find_or_build_child(pid)
          child['state'] = CHILD_RUNNING_STATE if child['state'] == CHILD_STOPPED_STATE
          self
        end

        def mark_child_phase(pid, phase)
          find_or_build_child(pid)['state'] = phase
          self
        end

        def mark_child_stopped(pid)
          child = find_or_build_child(pid)
          child['state'] = CHILD_STOPPED_STATE
          stop_threads(child.fetch('threads'))
          self
        end

        def register_thread(process_pid:, worker_id:, thread_index:)
          ChildPayload.new(find_or_build_child(process_pid)).register_thread(worker_id:, thread_index:)
          self
        end

        def mark_thread_state(process_pid:, worker_id:, state:, thread_index: nil)
          inferred_thread_index = thread_index || worker_id.to_s[/thread-(\d+)\z/, 1]&.to_i || 1
          ChildPayload.new(find_or_build_child(process_pid)).mark_thread_state(
            worker_id:,
            state:,
            thread_index: inferred_thread_index
          )
          self
        end

        def stop_all
          @snapshot['phase'] = STOPPED_PHASE
          Array(@snapshot.fetch('child_processes')).each do |child|
            child['state'] = CHILD_STOPPED_STATE
            stop_threads(child.fetch('threads', []))
          end
          self
        end

        def to_h
          @payload
        end

        private

        def find_or_build_child(pid)
          child_processes = @snapshot.fetch('child_processes')
          child_processes.find { |entry| entry['pid'] == pid } || append_child(pid)
        end

        def append_child(pid)
          prune_stopped_children
          child = {
            'pid' => pid,
            'state' => CHILD_RUNNING_STATE,
            'thread_count' => @configuration.threads,
            'threads' => []
          }
          @snapshot.fetch('child_processes') << child
          sort_children
          child
        end

        def sort_children
          @snapshot.fetch('child_processes').sort_by! { |entry| entry['pid'] }
        end

        def prune_stopped_children
          @snapshot.fetch('child_processes').reject! { |entry| entry['state'] == CHILD_STOPPED_STATE }
        end

        def stop_threads(threads)
          Array(threads).each { |thread| thread['state'] = THREAD_STOPPED_STATE }
        end
      end

      attr_reader :control_socket_path, :instance_token, :path, :started_at

      def self.default_path(worker_id)
        slug = worker_id.to_s.gsub(/[^a-zA-Z0-9_-]+/, '-').gsub(/\A-+|-+\z/, '')
        basename = "karya-runtime-#{slug.empty? ? 'worker' : slug}-#{Process.pid}.json"
        File.join(Dir.tmpdir, basename)
      end

      def self.default_control_socket_path(path)
        base = path.delete_suffix('.json')
        candidate = "#{base}.sock"
        return candidate if socket_path_within_limit?(candidate)

        File.join('/tmp', "karya-#{Digest::SHA256.hexdigest(path)[0, 24]}.sock")
      end

      def self.socket_path_within_limit?(path)
        path.to_s.bytesize <= MAX_UNIX_SOCKET_PATH_BYTES
      end

      def self.read_payload!(path)
        raise InvalidRuntimeStateFileError, 'runtime state file path is required' if path.to_s.empty?

        payload = JSON.parse(File.read(path))
        validate_payload!(payload)
      rescue Errno::ENOENT
        raise InvalidRuntimeStateFileError, "runtime state file does not exist: #{path}"
      rescue JSON::ParserError => e
        raise InvalidRuntimeStateFileError, "runtime state file is not valid JSON: #{e.message}"
      end

      def self.read_snapshot!(path)
        RuntimeSnapshot.from_h(read_payload!(path).fetch('snapshot'))
      end

      def self.live_payload!(path)
        payload = read_payload!(path)
        supervisor_pid = payload.fetch('supervisor_pid')
        phase = payload.fetch('snapshot').fetch('phase')
        socket_path = payload.fetch('control_socket_path')
        instance_token = payload.fetch('instance_token')
        return payload if phase == STOPPED_PHASE
        return payload if process_alive?(supervisor_pid) && control_socket_live?(socket_path, instance_token)

        raise InvalidRuntimeStateFileError, "runtime state file is stale for pid #{supervisor_pid}"
      end

      def self.control_payload!(path)
        payload = read_payload!(path)
        socket_path = payload.fetch('control_socket_path')
        raise InvalidRuntimeStateFileError, "runtime control socket is missing: #{socket_path}" unless File.exist?(socket_path)
        raise InvalidRuntimeStateFileError, "runtime control socket path is not a Unix socket: #{socket_path}" unless File.socket?(socket_path)

        payload
      end

      def self.process_alive?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::EPERM
        true
      rescue Errno::ESRCH
        false
      end

      def self.control_socket_live?(socket_path, instance_token)
        return false unless File.socket?(socket_path)

        response = UNIXSocket.open(socket_path) do |socket|
          socket.write(JSON.generate('command' => 'ping', 'instance_token' => instance_token))
          socket.close_write
          JSON.parse(read_control_response(socket))
        end

        response.fetch('ok', false)
      rescue Errno::ENOENT,
             Errno::ECONNREFUSED,
             Errno::ENOTSOCK,
             Errno::EPIPE,
             Errno::EPERM,
             Errno::EINVAL,
             JSON::ParserError,
             IOError
        false
      end

      def self.validate_payload!(payload)
        unless payload.is_a?(Hash) && payload.fetch('schema_version') == SCHEMA_VERSION
          raise InvalidRuntimeStateFileError, 'runtime state file has an unsupported schema version'
        end

        updated_at = payload.fetch('updated_at')
        started_at = payload.fetch('started_at')
        instance_token = payload.fetch('instance_token')
        control_socket_path = payload.fetch('control_socket_path')
        supervisor_pid = payload.fetch('supervisor_pid')
        raise InvalidRuntimeStateFileError, 'runtime state file updated_at must be a String' unless updated_at.is_a?(String)
        raise InvalidRuntimeStateFileError, 'runtime state file started_at must be a String' unless started_at.is_a?(String)
        raise InvalidRuntimeStateFileError, 'runtime state file instance_token must be a String' unless instance_token.is_a?(String)
        raise InvalidRuntimeStateFileError, 'runtime state file control_socket_path must be a String' unless control_socket_path.is_a?(String)
        raise InvalidRuntimeStateFileError, 'runtime state file supervisor_pid must be an Integer' unless supervisor_pid.is_a?(Integer)

        validate_snapshot!(payload.fetch('snapshot'))
        payload
      rescue KeyError => e
        raise InvalidRuntimeStateFileError, "runtime state file is missing #{e.message.delete_prefix('key not found: ')}"
      end

      def self.validate_snapshot!(snapshot)
        raise InvalidRuntimeStateFileError, 'runtime state file snapshot must be a Hash' unless snapshot.is_a?(Hash)

        validate_snapshot_fields!(snapshot)
        child_processes = snapshot.fetch('child_processes')
        raise InvalidRuntimeStateFileError, 'runtime state file child_processes must be an Array' unless child_processes.is_a?(Array)

        child_processes.each { |child| validate_child_snapshot!(child) }
      rescue KeyError => e
        raise InvalidRuntimeStateFileError, "runtime state file snapshot is missing #{e.message.delete_prefix('key not found: ')}"
      end

      def self.validate_child_snapshot!(child)
        raise InvalidRuntimeStateFileError, 'runtime state file child snapshot must be a Hash' unless child.is_a?(Hash)

        pid = child.fetch('pid')
        state = child.fetch('state')
        thread_count = child.fetch('thread_count')
        raise InvalidRuntimeStateFileError, 'runtime state file child pid must be an Integer' unless pid.is_a?(Integer)
        raise InvalidRuntimeStateFileError, "runtime state file child state must be one of: #{CHILD_STATES.join(', ')}" unless CHILD_STATES.include?(state)

        raise InvalidRuntimeStateFileError, 'runtime state file child thread_count must be an Integer' unless thread_count.is_a?(Integer)

        threads = child.fetch('threads')
        raise InvalidRuntimeStateFileError, 'runtime state file child threads must be an Array' unless threads.is_a?(Array)

        threads.each { |thread| validate_thread_snapshot!(thread) }
      rescue KeyError => e
        raise InvalidRuntimeStateFileError, "runtime state file child snapshot is missing #{e.message.delete_prefix('key not found: ')}"
      end

      def self.validate_thread_snapshot!(thread)
        raise InvalidRuntimeStateFileError, 'runtime state file thread snapshot must be a Hash' unless thread.is_a?(Hash)

        worker_id = thread.fetch('worker_id')
        state = thread.fetch('state')
        raise InvalidRuntimeStateFileError, 'runtime state file thread worker_id must be a String' unless worker_id.is_a?(String)
        raise InvalidRuntimeStateFileError, "runtime state file thread state must be one of: #{THREAD_STATES.join(', ')}" unless THREAD_STATES.include?(state)

        thread_index = thread.fetch('thread_index')
        raise InvalidRuntimeStateFileError, 'runtime state file thread_index must be an Integer' unless thread_index.is_a?(Integer)
      rescue KeyError => e
        raise InvalidRuntimeStateFileError, "runtime state file thread snapshot is missing #{e.message.delete_prefix('key not found: ')}"
      end

      def initialize(configuration:, path: nil, supervisor_pid: Process.pid, **metadata)
        @configuration = configuration
        store_class = self.class
        @path = path || store_class.default_path(configuration.worker_id)
        @supervisor_pid = supervisor_pid
        @started_at = metadata.fetch(:started_at, Time.now.utc).utc.iso8601
        @instance_token = metadata.fetch(:instance_token, SecureRandom.hex(16))
        @control_socket_path = metadata.fetch(:control_socket_path, store_class.default_control_socket_path(@path))
        validate_control_socket_path!
      end

      def snapshot
        RuntimeSnapshot.from_h(read_payload.fetch('snapshot'))
      end

      def write_running
        update_payload do |payload|
          prevent_live_supervisor_takeover!(payload)
          mutable_payload(payload).mark_running(
            @supervisor_pid,
            started_at: @started_at,
            instance_token: @instance_token,
            control_socket_path: @control_socket_path
          ).to_h
        end
      end
      alias write_running! write_running

      def mark_supervisor_phase(phase)
        update_payload { |payload| mutable_payload(payload).mark_supervisor_phase(phase).to_h }
      end

      def register_child(pid)
        update_payload { |payload| mutable_payload(payload).register_child(pid).to_h }
      end

      def mark_child_phase(pid, phase)
        update_payload { |payload| mutable_payload(payload).mark_child_phase(pid, phase).to_h }
      end

      def mark_child_stopped(pid)
        update_payload { |payload| mutable_payload(payload).mark_child_stopped(pid).to_h }
      end

      def register_thread(process_pid:, worker_id:, thread_index:)
        update_payload do |payload|
          mutable_payload(payload).register_thread(process_pid:, worker_id:, thread_index:).to_h
        end
      end

      def mark_thread_state(process_pid:, worker_id:, state:, thread_index: nil)
        update_payload do |payload|
          mutable_payload(payload).mark_thread_state(process_pid:, worker_id:, state:, thread_index:).to_h
        end
      end

      def write_stopped
        update_payload { |payload| mutable_payload(payload).stop_all.to_h }
      end
      alias write_stopped! write_stopped

      private

      def validate_control_socket_path!
        return if self.class.socket_path_within_limit?(@control_socket_path)

        raise InvalidWorkerSupervisorConfigurationError,
              "runtime control socket path is too long (max #{MAX_UNIX_SOCKET_PATH_BYTES} bytes): #{@control_socket_path}"
      end

      def mutable_payload(payload)
        MutablePayload.new(payload:, configuration: @configuration)
      end

      def blank_payload
        {
          'schema_version' => SCHEMA_VERSION,
          'updated_at' => Time.now.utc.iso8601,
          'started_at' => @started_at,
          'instance_token' => @instance_token,
          'control_socket_path' => @control_socket_path,
          'supervisor_pid' => @supervisor_pid,
          'snapshot' => {
            'worker_id' => @configuration.worker_id,
            'supervisor_pid' => @supervisor_pid,
            'queues' => @configuration.queues,
            'configured_processes' => @configuration.processes,
            'configured_threads' => @configuration.threads,
            'phase' => STOPPED_PHASE,
            'child_processes' => []
          }
        }
      end

      def read_payload
        payload = JSON.parse(File.read(path))
        self.class.validate_payload!(payload)
        normalized_payload(payload)
      rescue Errno::ENOENT
        blank_payload
      rescue JSON::ParserError => e
        raise InvalidRuntimeStateFileError, "runtime state file is not valid JSON: #{e.message}"
      end

      def update_payload(initial_payload: nil)
        ensure_parent_directory
        File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock_file|
          with_lock_timeout(lock_file) do
            payload = yield(initial_payload || read_payload)
            payload['updated_at'] = Time.now.utc.iso8601
            write_payload(payload)
          end
        end
      end

      def ensure_parent_directory
        FileUtils.mkdir_p(File.dirname(path))
      end

      def lock_path
        "#{path}.lock"
      end

      def with_lock_timeout(lock_file)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + LOCK_TIMEOUT_SECONDS
        sleep(LOCK_RETRY_INTERVAL) until attempt_lock?(lock_file, deadline)

        yield
      ensure
        lock_file.flock(File::LOCK_UN)
      end

      def write_payload(payload)
        AtomicPayloadWriter.new(path:, payload:).write
      end

      def attempt_lock?(lock_file, deadline)
        return true if lock_file.flock(File::LOCK_EX | File::LOCK_NB)
        raise InvalidRuntimeStateFileError, "timed out acquiring runtime state lock for #{path}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        false
      end

      def normalized_payload(payload)
        blank_snapshot = blank_payload.fetch('snapshot')
        snapshot = blank_snapshot.merge(payload.fetch('snapshot', {}))
        blank_payload.merge(payload).merge('snapshot' => snapshot)
      end

      def self.validate_queue_snapshot!(queues)
        raise InvalidRuntimeStateFileError, 'runtime state file queues must be an Array' unless queues.is_a?(Array)
        return if queues.all?(String)

        raise InvalidRuntimeStateFileError, 'runtime state file queues entries must all be Strings'
      end

      def self.validate_snapshot_fields!(snapshot)
        worker_id = snapshot.fetch('worker_id')
        supervisor_pid = snapshot.fetch('supervisor_pid')
        queues = snapshot.fetch('queues')
        configured_processes = snapshot.fetch('configured_processes')
        configured_threads = snapshot.fetch('configured_threads')
        phase = snapshot.fetch('phase')
        raise InvalidRuntimeStateFileError, 'runtime state file worker_id must be a String' unless worker_id.is_a?(String)
        raise InvalidRuntimeStateFileError, 'runtime state file snapshot supervisor_pid must be an Integer' unless supervisor_pid.is_a?(Integer)

        validate_queue_snapshot!(queues)
        raise InvalidRuntimeStateFileError, 'runtime state file configured_processes must be an Integer' unless configured_processes.is_a?(Integer)
        raise InvalidRuntimeStateFileError, 'runtime state file configured_threads must be an Integer' unless configured_threads.is_a?(Integer)

        return if SNAPSHOT_PHASES.include?(phase)

        raise InvalidRuntimeStateFileError, "runtime state file phase must be one of: #{SNAPSHOT_PHASES.join(', ')}"
      end

      private_class_method :control_socket_live?, :validate_queue_snapshot!, :validate_snapshot_fields!

      def self.read_control_response(socket)
        buffer = +''
        loop do
          return buffer unless socket.wait_readable(CONTROL_SOCKET_TIMEOUT_SECONDS)

          buffer << socket.readpartial(1024)
        end
      rescue EOFError
        buffer
      end

      private_class_method :read_control_response

      def prevent_live_supervisor_takeover!(payload)
        existing_pid = payload.fetch('supervisor_pid')
        existing_phase = payload.fetch('snapshot').fetch('phase')
        existing_token = payload.fetch('instance_token')
        return if existing_phase == STOPPED_PHASE
        return unless self.class.process_alive?(existing_pid)
        return if existing_pid == @supervisor_pid && existing_token == @instance_token

        raise RuntimeControlUnavailableError,
              "runtime state file is already owned by live supervisor pid #{existing_pid}: #{path}"
      end

      # Writes runtime state JSON through a temp file before an atomic rename.
      class AtomicPayloadWriter
        def initialize(path:, payload:)
          @path = path
          @payload = payload
          @tempfile = nil
        end

        def write
          Tempfile.create(['karya-runtime-state', '.json'], File.dirname(@path)) do |tempfile|
            @tempfile = tempfile
            write_payload
            flush_payload
            publish_payload
          end
        end

        private

        def write_payload
          @tempfile.write(JSON.pretty_generate(@payload))
        end

        def flush_payload
          @tempfile.flush
          @tempfile.fsync
        end

        def publish_payload
          FileUtils.mv(@tempfile.path, @path)
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
