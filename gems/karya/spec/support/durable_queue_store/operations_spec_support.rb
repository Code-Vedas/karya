# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.shared_context 'with durable queue-store operations spec support' do
  let(:now) { Time.utc(2026, 5, 23, 12, 0, 0) }
  let(:policy_set) { Karya::Backpressure::PolicySet.new }
  let(:circuit_breaker_policy_set) { Karya::CircuitBreaker::PolicySet.new }
  let(:store_class) do
    Struct.new(:policy_set, :circuit_breaker_policy_set, :max_batch_size, keyword_init: true)
  end
  let(:store) do
    store_class.new(policy_set:, circuit_breaker_policy_set:, max_batch_size: 10).tap do |instance|
      instance.define_singleton_method(:token_generator) { -> { 'token' } }
    end
  end
  let(:namespace) { 'spec' }

  def job(id:, state:, queue: 'billing', handler: 'ProcessInvoice', **attributes)
    Karya::Job.new(
      id:,
      queue:,
      handler:,
      arguments: {},
      state:,
      created_at: attributes.fetch(:created_at, Time.utc(2026, 5, 23, 11, 59, 0)),
      updated_at: attributes.fetch(:updated_at, Time.utc(2026, 5, 23, 11, 59, 0)),
      **attributes.except(:created_at, :updated_at)
    )
  end

  def job_row(job)
    Karya::Internal::DurableQueueStore::JobRecord.new(namespace:, job:).to_h
  end

  def queue_entry_row(job, insertion_sequence: 1)
    Karya::Internal::DurableQueueStore::QueueEntryRecord.new(
      namespace:,
      job:,
      insertion_sequence:
    ).to_h
  end

  def reservation_row(job:, token:, phase:, worker_id: 'worker-1', expires_at: now + 60)
    Karya::Internal::DurableQueueStore::ReservationRecord.new(
      namespace:,
      reservation: Karya::Reservation.new(
        token:,
        job_id: job.id,
        queue: job.queue,
        worker_id:,
        reserved_at: now - 30,
        expires_at:
      ),
      phase:
    ).to_h
  end

  def workflow_batch_row(batch_id:)
    registration = Struct.new(:workflow_id, :workflow_family, :workflow_version).new('workflow-1', 'billing', 'v1')
    batch = Karya::Workflow::Batch.new(
      id: batch_id,
      job_ids: ['job-1'],
      created_at: now,
      updated_at: now
    )
    Karya::Internal::DurableQueueStore::WorkflowBatchRecord.new(
      namespace:,
      batch:,
      registration:,
      jobs_by_id: { 'job-1' => job(id: 'job-1', state: :queued) }
    ).to_h
  end

  def workflow_step_row(batch_id:, step_id:, job_id:, _step_sequence: nil)
    workflow_job = job(id: job_id, state: :queued)
    registration = Struct.new(
      :dependency_job_ids_by_job_id,
      :step_job_ids,
      :approval_requirements_by_job_id,
      :interaction_requirements_by_job_id,
      :compensation_jobs_by_step_id,
      :child_workflow_ids_by_step_id
    ).new({}, { step_id => job_id }, {}, {}, {}, {})
    state_class = Class.new do
      def workflow_approval_decision_for(_job_id); end
      def workflow_interaction_received_at(batch_id:, kind:, name:); end
      def workflow_pause_requested_at(_batch_id); end
      def workflow_rollbacks_by_batch_id; end
    end
    state = instance_double(
      state_class,
      workflow_approval_decision_for: nil,
      workflow_interaction_received_at: nil,
      workflow_pause_requested_at: nil,
      workflow_rollbacks_by_batch_id: {}
    )
    context = Karya::Internal::DurableQueueStore::WorkflowStepRecord::Context.new(
      registration:,
      state:
    )
    Karya::Internal::DurableQueueStore::WorkflowStepRecord.new(
      namespace:,
      batch_id:,
      step_id:,
      job: workflow_job,
      context:
    ).to_h
  end

  def policy_row(policy_kind:, scope_kind:, scope_value:, state_payload:)
    Karya::Internal::DurableQueueStore::PolicyStateRecord.new(
      namespace:,
      policy_kind:,
      scope: { kind: scope_kind, value: scope_value },
      state_payload:,
      updated_at: now
    ).to_h
  end

  def context(rows:, metadata: { reservation_token_sequence: 0 })
    Karya::Internal::DurableQueueStore::OperationContext.new(namespace:, request: {}, metadata:, rows:)
  end

  def empty_rows
    {
      jobs: [],
      queue_entries: [],
      reservations: [],
      idempotency_keys: [],
      uniqueness_keys: [],
      policy_state: [],
      workflow_batches: [],
      workflow_steps: [],
      workflow_interactions: [],
      workflow_history: []
    }
  end

  def primary_keys_for(group_name)
    {
      jobs: %i[job_id],
      queue_entries: %i[queue job_id],
      reservations: %i[reservation_token],
      idempotency_keys: %i[idempotency_key],
      uniqueness_keys: %i[uniqueness_scope uniqueness_key],
      policy_state: %i[policy_kind scope_kind scope_value],
      workflow_batches: %i[batch_id],
      workflow_steps: %i[batch_id step_id],
      workflow_interactions: %i[batch_id sequence],
      workflow_history: %i[batch_id sequence]
    }.fetch(group_name)
  end

  def replace_group_rows(updated_rows, group_name, group_rows)
    keys = primary_keys_for(group_name)
    group_rows.each do |replacement_row|
      index = updated_rows.fetch(group_name).index do |row|
        keys.all? { |key| row.fetch(key) == replacement_row.fetch(key) }
      end
      updated_rows.fetch(group_name)[index] = replacement_row if index
    end
  end

  def remove_group_rows(updated_rows, group_name, group_rows)
    keys = primary_keys_for(group_name)
    updated_rows[group_name] = updated_rows.fetch(group_name).reject do |row|
      group_rows.any? { |candidate| keys.all? { |key| candidate.fetch(key) == row.fetch(key) } }
    end
  end

  def apply_plan(rows, plan)
    updated_rows = empty_rows.merge(rows).transform_values(&:dup)
    plan.inserts.each do |group_name, group_rows|
      updated_rows[group_name] += group_rows
    end
    plan.updates.each do |group_name, group_rows|
      replace_group_rows(updated_rows, group_name, group_rows)
    end
    plan.deletes.each do |group_name, group_rows|
      remove_group_rows(updated_rows, group_name, group_rows)
    end
    updated_rows.transform_values(&:freeze).freeze
  end

  def run_operation(operation_class, rows:, request:, operation_name:, metadata: { reservation_token_sequence: 0 })
    result = operation_class.new(store:, request:, operation_name:).call(context: context(rows:, metadata:))
    [apply_plan(rows, result.mutation_plan), result]
  end

  def workflow_enqueue_rows(definition:, jobs_by_step_id:, batch_id:, compensation_jobs_by_step_id: {})
    rows, _result = run_operation(
      Karya::Internal::DurableQueueStore::Operations::EnqueueWorkflow,
      rows: empty_rows,
      request: {
        definition:,
        jobs_by_step_id:,
        compensation_jobs_by_step_id:,
        batch_id:,
        now:
      },
      operation_name: :enqueue_workflow
    )
    rows
  end

  def helper_class
    @helper_class ||= Class.new(Karya::Internal::DurableQueueStore::Operation) do
      include Karya::Internal::DurableQueueStore::Operations::RowSupport
      include Karya::Internal::DurableQueueStore::Operations::BulkMutationSupport
      include Karya::Internal::DurableQueueStore::Operations::DeadLetterRecoverySupport
      include Karya::Internal::DurableQueueStore::Operations::LeaseSupport
      include Karya::Internal::DurableQueueStore::Operations::ReliabilityPolicySupport

      def call(context:); end
    end
  end

  def empty_context
    context(rows: { jobs: [], queue_entries: [], reservations: [], workflow_batches: [] })
  end

  def reserve_gate_store
    store_class.new(
      policy_set: Karya::Backpressure::PolicySet.new(
        rate_limits: {
          'queue:billing' => Karya::Backpressure::RateLimitPolicy.new(limit: 1, period: 60, scope: 'queue:billing')
        }
      ),
      circuit_breaker_policy_set: Karya::CircuitBreaker::PolicySet.new(
        policies: {
          'queue:billing' => Karya::CircuitBreaker::Policy.new(
            failure_threshold: 1,
            window: 60,
            cooldown: 60,
            scope: 'queue:billing',
            half_open_limit: 1
          )
        }
      ),
      max_batch_size: 10
    )
  end

  def reserve_gate_rows
    paused_job = job(id: 'job-paused', state: :queued, queue: 'paused')
    mismatched_job = job(id: 'job-mismatch', state: :failed, queue: 'billing')
    rate_limited_job = job(
      id: 'job-rate',
      state: :queued,
      queue: 'billing',
      rate_limit_scope: Karya::Backpressure::Scope.new(kind: :queue, value: 'billing')
    )
    breaker_job = job(id: 'job-breaker', state: :queued, queue: 'billing')
    token_job = job(id: 'job-token', state: :queued, queue: 'billing')

    {
      token_job:,
      rows: {
        jobs: [
          job_row(paused_job),
          job_row(mismatched_job),
          job_row(rate_limited_job),
          job_row(breaker_job),
          job_row(token_job)
        ],
        queue_entries: [
          queue_entry_row(paused_job, insertion_sequence: 1),
          queue_entry_row(mismatched_job, insertion_sequence: 2).merge(state: 'queued'),
          queue_entry_row(rate_limited_job, insertion_sequence: 3),
          queue_entry_row(breaker_job, insertion_sequence: 4),
          queue_entry_row(token_job, insertion_sequence: 5)
        ],
        reservations: [],
        policy_state: [
          policy_row(policy_kind: 'paused_queue', scope_kind: 'queue', scope_value: 'paused', state_payload: { paused: true }),
          policy_row(policy_kind: 'breaker_state', scope_kind: 'queue', scope_value: 'billing', state_payload: { state: :open, cooldown_until: now + 60 }),
          policy_row(policy_kind: 'rate_limit_admissions', scope_kind: 'queue', scope_value: 'billing', state_payload: { 'timestamps' => [now - 5] }),
          policy_row(policy_kind: 'rate_limit_admissions', scope_kind: 'handler', scope_value: 'ProcessInvoice', state_payload: { 'timestamps' => [] })
        ],
        workflow_batches: [],
        workflow_steps: [],
        workflow_interactions: [],
        workflow_history: []
      }
    }
  end

  def rollback_helper_class
    @rollback_helper_class ||= Class.new(Karya::Internal::DurableQueueStore::Operation) do
      include Karya::Internal::DurableQueueStore::WorkflowRuntimeSupport

      def call(context:); end
    end
  end

  def workflow_runtime_helper_class
    @workflow_runtime_helper_class ||= Class.new(Karya::Internal::DurableQueueStore::Operation) do
      include Karya::Internal::DurableQueueStore::WorkflowRuntimeSupport
      include Karya::Internal::DurableQueueStore::Operations::WorkflowOperationSupport

      def call(context:); end
    end
  end

  def workflow_rows_with_states(definition:, jobs_by_step_id:, batch_id:, states_by_job_id:, compensation_jobs_by_step_id: {})
    base_rows = workflow_enqueue_rows(
      definition:,
      jobs_by_step_id:,
      compensation_jobs_by_step_id:,
      batch_id:
    )

    base_rows.merge(
      jobs: base_rows.fetch(:jobs).map do |row|
        state = states_by_job_id.fetch(row.fetch(:job_id), row.fetch(:state).to_sym)
        job_row(
          job(
            id: row.fetch(:job_id),
            state:,
            queue: row.fetch(:queue),
            handler: row.fetch(:handler),
            uniqueness_key: row[:uniqueness_key],
            uniqueness_scope: row[:uniqueness_scope]
          )
        )
      end,
      workflow_steps: base_rows.fetch(:workflow_steps).map do |row|
        state = states_by_job_id.fetch(row.fetch(:job_id), row.fetch(:state).to_sym)
        row.merge(state: state.to_s)
      end
    )
  end
end
