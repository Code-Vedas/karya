# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'timeout'
require 'monitor'
require_relative 'base'
require_relative 'job_lifecycle'
require_relative 'internal/retry_policy_resolver'
require_relative 'internal/runtime_support/iteration_limit'
require_relative 'internal/runtime_support/signal_restorer'
require_relative 'primitives/lifecycle'
require_relative 'primitives/identifier'
require_relative 'primitives/queue_list'
require_relative 'primitives/positive_finite_number'
require_relative 'primitives/non_negative_finite_number'
require_relative 'primitives/callable'
require_relative 'primitives/optional_callable'
require_relative 'retry_policy'
require_relative 'retry_policy_set'
require_relative 'worker/callable_execution'
require_relative 'worker/configuration'
require_relative 'worker/handler_execution'
require_relative 'worker/handler_registry'
require_relative 'worker/inactive_shutdown_controller'
require_relative 'worker/method_dispatcher'
require_relative 'worker/mutable_graph_copy'
require_relative 'worker/perform_execution'
require_relative 'worker/run_session'
require_relative 'worker/run_loop_decision'
require_relative 'worker/runtime'
require_relative 'worker/shutdown_controller'
require_relative 'worker/subscription'
require_relative 'worker/unsupported_execution'

module Karya
  # Raised when worker bootstrap input is invalid.
  class InvalidWorkerConfigurationError < Error; end

  # Raised when a reserved job cannot be mapped to executable code.
  class MissingHandlerError < Error; end

  # Single-process worker that reserves jobs, dispatches handlers, and persists outcomes.
  class Worker
    # Sentinel class for a loop iteration that should keep polling.
    ContinueRunning = Class.new
    # Sentinel class for work released after a lease loss.
    LeaseLost = Class.new
    # Sentinel class for an iteration with no executable work.
    NoWorkAvailable = Class.new
    # Raised only by worker-enforced execution timeout guards.
    class WorkerExecutionTimeoutError < StandardError
      DEFAULT_MESSAGE = 'worker execution timed out'
    end

    DEFAULT_POLL_INTERVAL = 1
    CONTINUE_RUNNING = ContinueRunning
    LEASE_LOST = LeaseLost
    NO_WORK_AVAILABLE = NoWorkAvailable
    NOOP_SUBSCRIPTION = -> {}.freeze
    SIGNALS = %w[INT TERM].freeze

    def initialize(queue_store:, configuration: nil, runtime: nil, **options)
      extracted_options = options.dup
      @queue_store = queue_store
      @configuration = configuration || Configuration.from_options(extracted_options)
      @runtime = runtime || Runtime.from_options(extracted_options)
      @last_reported_runtime_state = nil
      raise_unknown_option_error(extracted_options) unless extracted_options.empty?
    end

    def worker_id
      configuration.worker_id
    end

    def queues
      configuration.queues
    end

    def handlers
      configuration.handlers
    end

    def lease_duration
      configuration.lease_duration
    end

    def subscription
      configuration.subscription
    end

    def lifecycle
      configuration.lifecycle
    end

    def retry_policy
      configuration.retry_policy
    end

    def default_execution_timeout
      configuration.default_execution_timeout
    end

    def work_once
      result = work_once_result(ShutdownController.inactive)
      return nil if [NO_WORK_AVAILABLE, LEASE_LOST].include?(result)

      result
    end

    def run(poll_interval: DEFAULT_POLL_INTERVAL, max_iterations: nil, stop_when_idle: false, shutdown_controller: nil)
      @last_reported_runtime_state = nil
      normalized_poll_interval = Primitives::NonNegativeFiniteNumber.new(
        :poll_interval,
        poll_interval,
        error_class: InvalidWorkerConfigurationError
      ).normalize
      iteration_limit = Internal::RuntimeSupport::IterationLimit.new(
        max_iterations,
        error_class: InvalidWorkerConfigurationError
      )
      shutdown_controller ||= ShutdownController.new
      run_loop = RunSession.new(worker: self, iteration_limit:, normalized_poll_interval:, shutdown_controller:, stop_when_idle:).method(:call)
      run_session = lambda do
        recover_orphaned_jobs
        run_loop.call
      end

      return run_session.call unless shutdown_controller.is_a?(ShutdownController)

      with_shutdown_handlers(shutdown_controller, &run_session)
    end

    private

    attr_reader :configuration, :queue_store, :runtime

    def work_once_result(shutdown_controller)
      return NO_WORK_AVAILABLE if shutdown_controller.stop_before_reserve?

      reservation = reserve_next or return NO_WORK_AVAILABLE

      reservation_token = reservation.token
      release_result = release_reserved_job_if_stopping_after_reserve(shutdown_controller, reservation_token)
      return release_result if release_result

      running_job = acquire_running_job(shutdown_controller, reservation_token)
      return running_job if running_job.equal?(NO_WORK_AVAILABLE)
      return LEASE_LOST if running_job.equal?(LEASE_LOST)
      return running_job if running_job.state == :failed

      begin
        execute_handler(running_job)
      rescue WorkerExecutionTimeoutError
        return fail_execution_job(reservation_token, running_job, failure_classification: :timeout)
      rescue StandardError
        return fail_execution_job(reservation_token, running_job, failure_classification: :error)
      end

      complete_execution_job(reservation_token)
    end

    def reserve_next
      reservation = queue_store.reserve(
        queues: subscription.queues,
        handler_names: subscription.handler_names,
        worker_id:,
        lease_duration:,
        now: current_time
      )
      return nil unless reservation

      instrument('worker.job.reserved', reservation_token: reservation.token, job_id: reservation.job_id, queue: reservation.queue)
      reservation
    end

    def current_time
      runtime.current_time
    end

    def recover_orphaned_jobs
      jobs = queue_store.recover_orphaned_jobs(worker_id:, now: current_time)
      instrument('worker.recovery.orphaned_jobs', recovered_jobs: jobs.length)
      jobs
    end

    def with_shutdown_handlers(shutdown_controller)
      restorers = []
      register_shutdown_restorers(restorers, shutdown_controller)
      yield
    ensure
      restorers ||= []
      restorers.reverse_each(&:call)
    end

    def register_shutdown_restorers(restorers, shutdown_controller)
      SIGNALS.each do |signal|
        restorers << runtime.subscribe_signal(signal, -> { shutdown_controller.advance })
      end
    end

    def release_reserved_job(reservation_token)
      queue_store.release(reservation_token:, now: current_time)
      instrument('worker.job.released', reservation_token:)
      NO_WORK_AVAILABLE
    rescue ExpiredReservationError, UnknownReservationError
      LEASE_LOST
    end

    def release_reserved_job_if_stopping_after_reserve(shutdown_controller, reservation_token)
      release_reserved_job_if_stopping(shutdown_controller, reservation_token)
    end

    def release_reserved_job_if_stopping_before_execution(shutdown_controller, reservation_token)
      # Re-check the same shutdown predicate at the last safe checkpoint before execution starts.
      release_reserved_job_if_stopping(shutdown_controller, reservation_token)
    end

    def acquire_running_job(shutdown_controller, reservation_token)
      pre_execution_transition(shutdown_controller, reservation_token)
    end

    def pre_execution_transition(shutdown_controller, reservation_token)
      shutdown_controller.synchronize_pre_execution do
        release_reserved_job_if_stopping_before_execution(shutdown_controller, reservation_token) || start_execution_job(reservation_token)
      end
    end

    def release_reserved_job_if_stopping(shutdown_controller, reservation_token)
      return unless shutdown_controller.stop_after_reserve?

      report_runtime_state('stopping')
      release_reserved_job(reservation_token)
    end

    def complete_execution_job(reservation_token)
      job = queue_store.complete_execution(reservation_token:, now: current_time)
      instrument('worker.job.succeeded', reservation_token:, job_id: job.id, handler: job.handler, queue: job.queue)
      job
    rescue ExpiredReservationError, UnknownReservationError
      LEASE_LOST
    end

    def fail_execution_job(reservation_token, running_job, failure_classification:)
      job = queue_store.fail_execution(
        reservation_token:,
        now: current_time,
        retry_policy: effective_retry_policy_for(running_job),
        failure_classification:
      )
      instrument('worker.job.failed', reservation_token:, job_id: job.id, handler: job.handler, queue: job.queue)
      job
    rescue ExpiredReservationError, UnknownReservationError
      LEASE_LOST
    end

    def start_execution_job(reservation_token)
      job = queue_store.start_execution(reservation_token:, now: current_time)
      payload = { reservation_token:, job_id: job.id, handler: job.handler, queue: job.queue }
      if job.state == :failed
        instrument('worker.job.failed', **payload)
        return job
      end

      report_runtime_state('running')
      instrument('worker.job.started', **payload)
      job
    rescue ExpiredReservationError, UnknownReservationError
      LEASE_LOST
    end

    def instrument(event, **payload)
      runtime.instrument(event, payload.merge(worker_id:))
    end

    def effective_retry_policy_for(job)
      job.retry_policy || retry_policy
    end

    def effective_execution_timeout_for(job)
      job.execution_timeout || default_execution_timeout
    end

    def execute_handler(job)
      execution_timeout = effective_execution_timeout_for(job)
      if execution_timeout
        Timeout.timeout(execution_timeout, WorkerExecutionTimeoutError, WorkerExecutionTimeoutError::DEFAULT_MESSAGE) do
          handlers.fetch(job.handler).call(arguments: job.arguments)
        end
      else
        handlers.fetch(job.handler).call(arguments: job.arguments)
      end

      nil
    end

    def report_runtime_state(state)
      return if @last_reported_runtime_state == state

      runtime.report_state(worker_id:, state:)
      @last_reported_runtime_state = state
    end

    def raise_unknown_option_error(options)
      raise InvalidWorkerConfigurationError, "unknown keyword options: #{options.keys.join(', ')}"
    end

    private_constant :CallableExecution,
                     :ContinueRunning,
                     :CONTINUE_RUNNING,
                     :Configuration,
                     :HandlerExecution,
                     :HandlerRegistry,
                     :InactiveShutdownController,
                     :LeaseLost,
                     :LEASE_LOST,
                     :MethodDispatcher,
                     :MutableGraphCopy,
                     :NoWorkAvailable,
                     :NOOP_SUBSCRIPTION,
                     :NO_WORK_AVAILABLE,
                     :PerformExecution,
                     :Runtime,
                     :RunSession,
                     :RunLoopDecision,
                     :SIGNALS,
                     :ShutdownController,
                     :UnsupportedExecution,
                     :WorkerExecutionTimeoutError
  end
end
