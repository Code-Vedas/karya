# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'monitor'
require_relative 'base'
require_relative 'job_lifecycle'
require_relative 'internal/runtime_support/iteration_limit'
require_relative 'internal/runtime_support/signal_restorer'
require_relative 'primitives/lifecycle'
require_relative 'primitives/identifier'
require_relative 'primitives/queue_list'
require_relative 'primitives/positive_finite_number'
require_relative 'primitives/non_negative_finite_number'
require_relative 'primitives/callable'
require_relative 'primitives/optional_callable'
require_relative 'worker/callable_execution'
require_relative 'worker/configuration'
require_relative 'worker/handler_execution'
require_relative 'worker/handler_registry'
require_relative 'worker/inactive_shutdown_controller'
require_relative 'worker/method_dispatcher'
require_relative 'worker/mutable_graph_copy'
require_relative 'worker/perform_execution'
require_relative 'worker/run_loop_decision'
require_relative 'worker/runtime'
require_relative 'worker/shutdown_controller'
require_relative 'worker/unsupported_execution'

module Karya
  # Raised when worker bootstrap input is invalid.
  class InvalidWorkerConfigurationError < Error; end

  # Raised when a reserved job cannot be mapped to executable code.
  class MissingHandlerError < Error; end

  # Single-process worker that reserves jobs, dispatches handlers, and persists outcomes.
  class Worker
    DEFAULT_POLL_INTERVAL = 1
    CONTINUE_RUNNING = Object.new
    LEASE_LOST = Object.new
    NO_WORK_AVAILABLE = Object.new
    NOOP_SUBSCRIPTION = -> {}.freeze
    SIGNALS = %w[INT TERM].freeze

    def initialize(queue_store:, configuration: nil, runtime: nil, **options)
      extracted_options = options.dup
      @queue_store = queue_store
      @configuration = configuration || Configuration.from_options(extracted_options)
      @runtime = runtime || Runtime.from_options(extracted_options)
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

    def lifecycle
      configuration.lifecycle
    end

    def work_once
      result = work_once_result(ShutdownController.inactive)
      case result
      when NO_WORK_AVAILABLE, LEASE_LOST
        nil
      else
        result
      end
    end

    def run(poll_interval: DEFAULT_POLL_INTERVAL, max_iterations: nil, stop_when_idle: false, shutdown_controller: nil)
      normalized_poll_interval = Primitives::NonNegativeFiniteNumber.new(:poll_interval, poll_interval, error_class: InvalidWorkerConfigurationError).normalize
      iteration_limit = Internal::RuntimeSupport::IterationLimit.new(
        max_iterations,
        error_class: InvalidWorkerConfigurationError
      )
      iterations = 0
      shutdown_controller ||= ShutdownController.new

      run_loop = lambda do
        loop do
          return nil if shutdown_controller.force_stop?

          instrument('worker.poll', queues:, stop_when_idle:, max_iterations: iteration_limit.normalize)
          result = work_once_result(shutdown_controller)
          iterations += 1
          idle = result.equal?(NO_WORK_AVAILABLE)
          lease_lost = result.equal?(LEASE_LOST)
          loop_result = RunLoopDecision.new(
            result:,
            state: {
              idle:,
              iterations:,
              iteration_limit:,
              lease_lost:,
              shutdown_controller:,
              stop_when_idle:
            }
          ).resolve
          return loop_result unless loop_result.equal?(CONTINUE_RUNNING)

          runtime.sleep(normalized_poll_interval) if (idle || lease_lost) && normalized_poll_interval.positive?
        end
      end

      return run_loop.call unless shutdown_controller.is_a?(ShutdownController)

      with_shutdown_handlers(shutdown_controller, &run_loop)
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

      begin
        handlers.fetch(running_job.handler).call(arguments: running_job.arguments)
      rescue StandardError
        return fail_execution_job(reservation_token)
      end

      complete_execution_job(reservation_token)
    end

    def reserve_next
      queues.each do |queue|
        reservation = queue_store.reserve(
          queue:,
          worker_id:,
          lease_duration:,
          now: current_time
        )
        next unless reservation

        instrument('worker.job.reserved', reservation_token: reservation.token, job_id: reservation.job_id, queue:)
        return reservation
      end

      nil
    end

    def current_time
      runtime.current_time
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

      release_reserved_job(reservation_token)
    end

    def complete_execution_job(reservation_token)
      job = queue_store.complete_execution(reservation_token:, now: current_time)
      instrument('worker.job.succeeded', reservation_token:, job_id: job.id, handler: job.handler, queue: job.queue)
      job
    rescue ExpiredReservationError, UnknownReservationError
      LEASE_LOST
    end

    def fail_execution_job(reservation_token)
      job = queue_store.fail_execution(reservation_token:, now: current_time)
      instrument('worker.job.failed', reservation_token:, job_id: job.id, handler: job.handler, queue: job.queue)
      job
    rescue ExpiredReservationError, UnknownReservationError
      LEASE_LOST
    end

    def start_execution_job(reservation_token)
      job = queue_store.start_execution(reservation_token:, now: current_time)
      instrument('worker.job.started', reservation_token:, job_id: job.id, handler: job.handler, queue: job.queue)
      job
    rescue ExpiredReservationError, UnknownReservationError
      LEASE_LOST
    end

    def instrument(event, **payload)
      runtime.instrument(event, payload.merge(worker_id:))
    end

    def raise_unknown_option_error(options)
      raise InvalidWorkerConfigurationError, "unknown keyword options: #{options.keys.join(', ')}"
    end

    private_constant :CallableExecution,
                     :CONTINUE_RUNNING,
                     :Configuration,
                     :HandlerExecution,
                     :HandlerRegistry,
                     :InactiveShutdownController,
                     :LEASE_LOST,
                     :MethodDispatcher,
                     :MutableGraphCopy,
                     :NOOP_SUBSCRIPTION,
                     :NO_WORK_AVAILABLE,
                     :PerformExecution,
                     :Runtime,
                     :RunLoopDecision,
                     :SIGNALS,
                     :ShutdownController,
                     :UnsupportedExecution
  end
end
