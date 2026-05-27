# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::WorkflowRuntimeSupport::RegistrationLoader do
  include_context 'with durable queue-store operations spec support'

  let(:helper) { workflow_runtime_helper_class.new(store:, request: {}, operation_name: :workflow_snapshot) }

  it 'rebuilds registration maps and supported interaction keys from durable rows' do
    definition = Karya::Workflow.define(:approval) do
      step :approve, handler: :approve, wait_for_approval: :approve_signal
      step :signal_step, handler: :signal_step, wait_for_signal: :ready_signal, depends_on: :approve
      step :event_step, handler: :event_step, wait_for_event: :ready_event, depends_on: :signal_step
    end
    rows = workflow_enqueue_rows(
      definition:,
      jobs_by_step_id: {
        approve: job(id: 'job-approve', state: :submission, handler: :approve),
        signal_step: job(id: 'job-signal', state: :submission, handler: :signal_step),
        event_step: job(id: 'job-event', state: :submission, handler: :event_step)
      },
      batch_id: :helper_batch
    )

    registration = helper.send(:registration_for_batch, rows, 'helper_batch')

    expect(registration.step_job_ids).to eq('approve' => 'job-approve', 'signal_step' => 'job-signal', 'event_step' => 'job-event')
    expect(registration.step_id_by_job_id).to eq('job-approve' => 'approve', 'job-signal' => 'signal_step', 'job-event' => 'event_step')
    expect(registration.dependency_job_ids_by_job_id).to eq(
      'job-approve' => [],
      'job-signal' => ['job-approve'],
      'job-event' => ['job-signal']
    )
    expect(registration.approval_requirements_by_job_id).to eq('job-approve' => { name: 'approve_signal' })
    expect(registration.interaction_requirements_by_job_id).to eq(
      'job-signal' => { kind: :signal, name: 'ready_signal' },
      'job-event' => { kind: :event, name: 'ready_event' }
    )
    expect(registration.interaction_supported_keys).to include(
      [:signal, 'approve_signal'] => true,
      [:signal, 'ready_signal'] => true,
      [:event, 'ready_event'] => true
    )
  end

  it 'normalizes string requirements and rejects missing workflow batches' do
    step_rows = [
      {
        step_id: :approve,
        job_id: 'job-approve',
        dependency_payload: Karya::Internal::DurableQueueStore::PayloadCodec.dump([]),
        metadata_payload: Karya::Internal::DurableQueueStore::PayloadCodec.dump(
          Karya::Internal::DurableQueueStore::PolicyStateRecord.stringify_payload(
            'approval_requirement' => { 'kind' => 'signal', 'name' => 'approve_signal' },
            'interaction_requirement' => { 'kind' => 'event', 'name' => 'invoice_event' },
            'compensation_job_id' => 'rollback-approve',
            'child_workflow_id' => 'child-approval'
          )
        )
      },
      {
        step_id: :plain,
        job_id: 'job-plain',
        dependency_payload: Karya::Internal::DurableQueueStore::PayloadCodec.dump([]),
        metadata_payload: nil
      }
    ]
    maps = Karya::Internal::DurableQueueStore::WorkflowRuntimeSupport::RegistrationMapsBuilder.new(step_rows:).to_h

    expect(maps.fetch(:approval_requirements_by_job_id)).to eq('job-approve' => { kind: :signal, name: 'approve_signal' })
    expect(maps.fetch(:interaction_requirements_by_job_id)).to eq('job-approve' => { kind: :event, name: 'invoice_event' })
    expect(maps.fetch(:compensation_jobs_by_step_id)).to eq(approve: 'rollback-approve')
    expect(maps.fetch(:child_workflow_ids_by_step_id)).to eq(approve: 'child-approval')
    expect(maps.fetch(:step_job_ids)).to include(plain: 'job-plain')
    expect do
      helper.send(:registration_for_batch, empty_rows, 'missing')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /is not a workflow batch/)
  end

  it 'adds approval signals to supported interaction keys' do
    supported_keys = helper.send(
      :interaction_supported_keys,
      { 'job-approve' => { name: 'approve_signal' } },
      { 'job-event' => { kind: 'event', name: 'invoice_event' } }
    )

    expect(supported_keys).to include([:signal, 'approve_signal'] => true, [:event, 'invoice_event'] => true)
  end
end
