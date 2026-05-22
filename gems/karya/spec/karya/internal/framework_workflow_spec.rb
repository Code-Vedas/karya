# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::FrameworkWorkflow do
  let(:job_class) do
    stub_const('Karya::FrameworkWorkflowSpecJob', Class.new(Karya::FrameworkJob::Base) do
      queue_as :billing

      def perform(account_id:, force: false)
        [account_id, force]
      end
    end)
  end
  let(:workflow_source) do
    defined_job = job_class
    Module.new.tap do |mod|
      mod.extend(Karya::Internal::FrameworkWorkflow::Source)
      mod.workflow :billing_flow do
        step :sync, job: defined_job, arguments: defined_job.arguments(account_id: 1)
      end
    end
  end
  let(:workflow_source_without_block) do
    Module.new.tap do |mod|
      mod.extend(Karya::Internal::FrameworkWorkflow::Source)
      mod.workflow :empty_flow
    end
  end
  let(:configuration) do
    instance_double(Karya::Internal::FrameworkConfiguration, workflow_sources: [workflow_source])
  end
  let(:queue_store) do
    instance_double(
      Karya::Internal::FrameworkWorkflow::QueueStoreFacade,
      enqueue_workflow: :started,
      batch_snapshot: :batch,
      workflow_snapshot: :snapshot,
      workflow_history: [:history],
      query_workflow: 'state',
      deliver_workflow_signal: :signal,
      deliver_workflow_event: :event,
      pause_workflow: :pause,
      resume_workflow: :resume,
      approve_workflow_checkpoints: :approve,
      reject_workflow_checkpoints: :reject,
      retry_workflow_steps: :retry,
      dead_letter_workflow_steps: :dead_letter,
      replay_workflow_steps: :replay,
      retry_dead_letter_workflow_steps: :retry_dead_letter,
      discard_workflow_steps: :discard,
      rollback_workflow: :rollback,
      enqueue_child_workflow: :child,
      sync_child_workflows: :sync_children
    )
  end
  let(:facade) do
    Karya::Internal::FrameworkWorkflow::Facade.new(
      configuration_provider: -> { configuration },
      queue_store:
    )
  end
  let(:catalog) { facade.catalog }
  let(:definition) { catalog.fetch(:billing_flow) }

  it 'builds catalogs and definitions' do
    queue_store_facade = Karya::Internal::FrameworkWorkflow::QueueStoreFacade.new(queue_store: queue_store)

    expect(catalog.resolve(workflow_family: definition.workflow_family)).to eq(definition)
    expect(catalog.fetch_version(workflow_family: definition.workflow_family, workflow_version: definition.workflow_version)).to eq(definition)
    expect(
      facade.define(:direct_flow, workflow_family: nil, workflow_version: nil, default_version: true) do |builder|
        builder.step(:sync, job: job_class)
      end
    ).to be_a(Karya::Internal::FrameworkWorkflow::Definition)
    expect(queue_store_facade.enqueue_workflow).to eq(:started)
    expect(queue_store_facade.batch_snapshot).to eq(:batch)
    expect(queue_store_facade.workflow_snapshot).to eq(:snapshot)
    expect(queue_store_facade.workflow_history).to eq([:history])
    expect(queue_store_facade.query_workflow).to eq('state')
    expect(queue_store_facade.deliver_workflow_signal).to eq(:signal)
    expect(queue_store_facade.deliver_workflow_event).to eq(:event)
    expect(queue_store_facade.pause_workflow).to eq(:pause)
    expect(queue_store_facade.resume_workflow).to eq(:resume)
    expect(queue_store_facade.approve_workflow_checkpoints).to eq(:approve)
    expect(queue_store_facade.reject_workflow_checkpoints).to eq(:reject)
    expect(queue_store_facade.retry_workflow_steps).to eq(:retry)
    expect(queue_store_facade.dead_letter_workflow_steps).to eq(:dead_letter)
    expect(queue_store_facade.replay_workflow_steps).to eq(:replay)
    expect(queue_store_facade.retry_dead_letter_workflow_steps).to eq(:retry_dead_letter)
    expect(queue_store_facade.discard_workflow_steps).to eq(:discard)
    expect(queue_store_facade.rollback_workflow).to eq(:rollback)
    expect(queue_store_facade.enqueue_child_workflow).to eq(:child)
    expect(queue_store_facade.sync_child_workflows).to eq(:sync_children)
  end

  it 'dispatches workflow lifecycle operations' do
    expect(facade.start(definition:, batch_id: 'batch-1', step_arguments: { sync: job_class.arguments(account_id: 2) })).to eq(:started)
    expect(facade.batch(batch_id: 'batch-1')).to eq(:batch)
    expect(facade.snapshot(batch_id: 'batch-1')).to eq(:snapshot)
    expect(facade.history(batch_id: 'batch-1')).to eq([:history])
    expect(facade.query(batch_id: 'batch-1', query: 'state')).to eq('state')
    expect(facade.signal(batch_id: 'batch-1', signal: :wake, payload: {})).to eq(:signal)
    expect(facade.event(batch_id: 'batch-1', event: :wake, payload: {})).to eq(:event)
    expect(facade.pause(batch_id: 'batch-1')).to eq(:pause)
    expect(facade.resume(batch_id: 'batch-1')).to eq(:resume)
  end

  it 'dispatches workflow recovery and child operations' do
    expect(facade.approve(batch_id: 'batch-1', step_ids: [:sync])).to eq(:approve)
    expect(facade.reject(batch_id: 'batch-1', step_ids: [:sync], reason: 'nope')).to eq(:reject)
    expect(facade.retry_steps(batch_id: 'batch-1', step_ids: [:sync])).to eq(:retry)
    expect(facade.dead_letter_steps(batch_id: 'batch-1', step_ids: [:sync], reason: 'dead')).to eq(:dead_letter)
    expect(facade.replay_steps(batch_id: 'batch-1', step_ids: [:sync])).to eq(:replay)
    expect(facade.retry_dead_letter_steps(batch_id: 'batch-1', step_ids: [:sync], next_retry_at: Time.now.utc)).to eq(:retry_dead_letter)
    expect(facade.discard_steps(batch_id: 'batch-1', step_ids: [:sync])).to eq(:discard)
    expect(facade.rollback(batch_id: 'batch-1', reason: 'rollback')).to eq(:rollback)
    expect(facade.enqueue_child(parent_batch_id: 'batch-1', parent_step_id: 'sync', definition:, batch_id: 'child-1', step_arguments: {})).to eq(:child)
    expect(facade.sync_children(parent_batch_id: 'batch-1')).to eq(:sync_children)
  end

  it 'rejects invalid workflow declarations and lookups' do
    builder = Karya::Internal::FrameworkWorkflow::DefinitionBuilder.new(:billing_flow, workflow_family: nil, workflow_version: nil, default_version: true)
    expect { builder.step(:sync, job: Object.new) }.to raise_error(ArgumentError, /framework job class/)
    expect { facade.catalog.fetch(:missing) }.to raise_error(Karya::Workflow::InvalidDefinitionError)
    expect { facade.catalog.fetch_version(workflow_family: :billing_flow, workflow_version: :v2) }.to raise_error(Karya::Workflow::InvalidDefinitionError)
    expect { facade.catalog.resolve(workflow_family: :missing) }.to raise_error(Karya::Workflow::InvalidDefinitionError)
    expect { facade.start(definition: Object.new, batch_id: 'batch', step_arguments: {}) }.to raise_error(ArgumentError, /definition must be/)
  end

  it 'normalizes raw workflow payloads and non-time values' do
    expect(described_class::Normalization.payload('raw')).to eq('raw')
    expect(described_class::Normalization.now(1.5)).to eq(Time.at(1.5).utc)
  end

  it 'omits missing compensation handlers and falls back to default payloads' do
    binding = described_class::StepBinding.new(
      id: :sync,
      job_class: job_class,
      arguments: {},
      compensation_job_class: nil,
      compensation_arguments: {},
      depends_on: nil,
      child_workflow: nil,
      wait_for_approval: nil,
      wait_for_signal: nil,
      wait_for_event: nil
    )
    registry = described_class::StepRegistry.new([binding])

    expect(binding.compensation_job_class).to be_nil
    expect(binding.to_core_definition(double(step: nil))).to be_nil
    expect(registry.compensation_job_classes).to eq({})
    expect(registry.materialize_jobs(step_arguments: {}, now: Time.now.utc, compensation: true)).to eq({})
    expect(registry.send(:resolved_payload, { 'sync' => 'payload' }, 'sync', {})).to eq('payload')
  end

  it 'tracks compensation job bindings when they are present' do
    binding = described_class::StepBinding.new(
      id: :sync,
      job_class: job_class,
      arguments: {},
      compensation_job_class: job_class,
      compensation_arguments: {},
      depends_on: nil,
      child_workflow: nil,
      wait_for_approval: nil,
      wait_for_signal: nil,
      wait_for_event: nil
    )
    registry = described_class::StepRegistry.new([binding])
    builder_class = Class.new do
      def step(*)
        nil
      end
    end
    builder = builder_class.new

    expect(binding.compensation_job_class).to eq(job_class)
    expect(binding.to_core_definition(builder)).to be_nil
    expect(registry.compensation_job_classes).to eq('sync' => job_class)
  end

  it 'supports workflow sources and direct definitions without blocks' do
    expect { workflow_source_without_block.karya_workflow_definitions }.to raise_error(Karya::Workflow::InvalidDefinitionError)
    expect do
      facade.define(:empty_direct, workflow_family: nil, workflow_version: nil, default_version: true)
    end.to raise_error(Karya::Workflow::InvalidDefinitionError)
    expect(facade.start(definition: :billing_flow, batch_id: 'batch-1', step_arguments: {})).to eq(:started)
  end

  it 'rejects duplicate workflow family defaults and versions' do
    allow(Karya::Workflow).to receive(:catalog).and_return(:catalog)
    definition_a = instance_double(
      Karya::Internal::FrameworkWorkflow::Definition,
      id: 'a',
      core_definition: instance_double(Karya::Workflow::Definition),
      workflow_family: 'billing',
      workflow_version: 'v1',
      default_version?: true
    )
    definition_b = instance_double(
      Karya::Internal::FrameworkWorkflow::Definition,
      id: 'b',
      core_definition: instance_double(Karya::Workflow::Definition),
      workflow_family: 'billing',
      workflow_version: 'v2',
      default_version?: true
    )
    definition_c = instance_double(
      Karya::Internal::FrameworkWorkflow::Definition,
      id: 'c',
      core_definition: instance_double(Karya::Workflow::Definition),
      workflow_family: 'billing',
      workflow_version: 'v1',
      default_version?: false
    )

    expect do
      described_class::Catalog.new(definitions: [definition_a, definition_b])
    end.to raise_error(Karya::Workflow::InvalidDefinitionError)

    expect do
      described_class::Catalog.new(definitions: [definition_a, definition_c])
    end.to raise_error(Karya::Workflow::InvalidDefinitionError)
  end

  it 'allows non-default workflow versions without adding them to the default family index' do
    allow(Karya::Workflow).to receive(:catalog).and_return(:catalog)
    non_default_definition = instance_double(
      Karya::Internal::FrameworkWorkflow::Definition,
      id: 'c',
      core_definition: instance_double(Karya::Workflow::Definition),
      workflow_family: 'billing',
      workflow_version: 'v2',
      default_version?: false
    )

    catalog = described_class::Catalog.new(definitions: [non_default_definition])

    expect(catalog.fetch('c')).to eq(non_default_definition)
    expect { catalog.resolve(workflow_family: 'billing') }.to raise_error(Karya::Workflow::InvalidDefinitionError)
  end
end
