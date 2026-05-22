# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'durable_queue_store/payload_codec'
require_relative '../reservation'
require_relative 'bulk_mutation'
require_relative 'dead_letter_reason'
require_relative 'failure_classification'
require_relative 'retry_policy_normalizer'
require_relative 'durable_queue_store/shared_support'
require_relative 'durable_queue_store/handler_matcher'
require_relative 'durable_queue_store/lease_duration'
require_relative 'durable_queue_store/request_support'
require_relative 'durable_queue_store/reservation_support'
require_relative 'durable_queue_store/operation_context'
require_relative 'durable_queue_store/mutation_plan'
require_relative 'durable_queue_store/operation_result'
require_relative 'durable_queue_store/operation'
require_relative 'durable_queue_store/sql_state_store'
require_relative 'durable_queue_store/duplicate_key_summary'
require_relative 'durable_queue_store/uniqueness_evaluator'
require_relative 'durable_queue_store/workflow_runtime_support'
require_relative 'durable_queue_store/operations/bulk_job_lookup'
require_relative 'durable_queue_store/operations/bulk_mutation_runner'
require_relative 'durable_queue_store/operations/batch_snapshot_value_builder'
require_relative 'durable_queue_store/operations/backpressure_snapshot_value_builder'
require_relative 'durable_queue_store/operations/circuit_breaker_snapshot_builder'
require_relative 'durable_queue_store/operations/job_row'
require_relative 'durable_queue_store/operations/job_runtime_rows'
require_relative 'durable_queue_store/operations/lease_context'
require_relative 'durable_queue_store/operations/policy_state_row'
require_relative 'durable_queue_store/operations/recovered_rows_applier'
require_relative 'durable_queue_store/operations/recovered_snapshot_rows_builder'
require_relative 'durable_queue_store/operations/release_result_builder'
require_relative 'durable_queue_store/operations/row_index'
require_relative 'durable_queue_store/operations/active_concurrency_counter'
require_relative 'durable_queue_store/operations/scope_key_set'
require_relative 'durable_queue_store/operations/start_execution_result_builder'
require_relative 'durable_queue_store/operations/stuck_jobs_snapshot_builder'
require_relative 'durable_queue_store/operations/stuck_job_recovery_merger'
require_relative 'durable_queue_store/operations/queue_entry_sequence'
require_relative 'durable_queue_store/operations/workflow_job_effects'
require_relative 'durable_queue_store/operations/workflow_batch_builder'
require_relative 'durable_queue_store/operations'
require_relative 'durable_queue_store/operations/reserve_candidate_selector'
require_relative 'durable_queue_store/operations/reserve_mutation_plan_builder'
require_relative 'durable_queue_store/operations/reserve_reservation_builder'
require_relative 'durable_queue_store/workflow_operations'
require_relative 'durable_queue_store/engine'
require_relative 'durable_queue_store/job_record'
require_relative 'durable_queue_store/queue_entry_record'
require_relative 'durable_queue_store/reservation_record'
require_relative 'durable_queue_store/idempotency_key_record'
require_relative 'durable_queue_store/uniqueness_key_record'
require_relative 'durable_queue_store/workflow_batch_record'
require_relative 'durable_queue_store/workflow_step_record'
require_relative 'durable_queue_store/workflow_history_record'
require_relative 'durable_queue_store/workflow_interaction_record'
require_relative 'durable_queue_store/policy_state_record'
require_relative 'durable_queue_store/persisted_adapter'

module Karya
  module Internal
    # Normalized durable-record builders for the next persisted queue-store model.
    module DurableQueueStore
    end
  end
end
