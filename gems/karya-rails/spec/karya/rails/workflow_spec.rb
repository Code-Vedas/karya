# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../rails_helper'

RSpec.describe Karya::Rails::Workflow do
  it 'delegates workflow definition and query operations to the shared facade' do
    facade = instance_double(Karya::Internal::FrameworkWorkflow::Facade)
    allow(described_class).to receive(:facade).and_return(facade)
    allow(facade).to receive_messages(
      define: :definition,
      catalog: :catalog,
      start: :start,
      batch: :batch,
      snapshot: :snapshot,
      history: :history,
      query: :query,
      signal: :signal,
      event: :event,
      pause: :pause,
      resume: :resume,
      approve: :approve,
      reject: :reject,
      retry_steps: :retry_steps,
      dead_letter_steps: :dead_letter_steps,
      replay_steps: :replay_steps,
      retry_dead_letter_steps: :retry_dead_letter_steps,
      discard_steps: :discard_steps,
      rollback: :rollback,
      enqueue_child: :enqueue_child,
      sync_children: :sync_children
    )

    expect(described_class.define(:billing)).to eq(:definition)
    expect(described_class.catalog).to eq(:catalog)
    expect(described_class.start(definition: :billing, batch_id: '1', step_arguments: {})).to eq(:start)
    expect(described_class.batch(batch_id: '1')).to eq(:batch)
    expect(described_class.snapshot(batch_id: '1')).to eq(:snapshot)
    expect(described_class.history(batch_id: '1')).to eq(:history)
    expect(described_class.query(batch_id: '1', query: 'state')).to eq(:query)
    expect(described_class.signal(batch_id: '1', signal: :wake, payload: {})).to eq(:signal)
    expect(described_class.event(batch_id: '1', event: :wake, payload: {})).to eq(:event)
    expect(described_class.pause(batch_id: '1')).to eq(:pause)
    expect(described_class.resume(batch_id: '1')).to eq(:resume)
  end

  it 'delegates workflow recovery operations to the shared facade' do
    facade = instance_double(Karya::Internal::FrameworkWorkflow::Facade)
    allow(described_class).to receive(:facade).and_return(facade)
    allow(facade).to receive_messages(
      approve: :approve,
      reject: :reject,
      retry_steps: :retry_steps,
      dead_letter_steps: :dead_letter_steps,
      replay_steps: :replay_steps,
      retry_dead_letter_steps: :retry_dead_letter_steps,
      discard_steps: :discard_steps,
      rollback: :rollback,
      enqueue_child: :enqueue_child,
      sync_children: :sync_children
    )

    expect(described_class.approve(batch_id: '1', step_ids: [:sync])).to eq(:approve)
    expect(described_class.reject(batch_id: '1', step_ids: [:sync], reason: 'nope')).to eq(:reject)
    expect(described_class.retry_steps(batch_id: '1', step_ids: [:sync])).to eq(:retry_steps)
    expect(described_class.dead_letter_steps(batch_id: '1', step_ids: [:sync], reason: 'nope')).to eq(:dead_letter_steps)
    expect(described_class.replay_steps(batch_id: '1', step_ids: [:sync])).to eq(:replay_steps)
    expect(described_class.retry_dead_letter_steps(batch_id: '1', step_ids: [:sync], next_retry_at: Time.now.utc)).to eq(:retry_dead_letter_steps)
    expect(described_class.discard_steps(batch_id: '1', step_ids: [:sync])).to eq(:discard_steps)
    expect(described_class.rollback(batch_id: '1', reason: 'rollback')).to eq(:rollback)
    expect(
      described_class.enqueue_child(
        parent_batch_id: '1',
        parent_step_id: 'sync',
        definition: :billing,
        batch_id: '2',
        step_arguments: {}
      )
    ).to eq(:enqueue_child)
    expect(described_class.sync_children(parent_batch_id: '1')).to eq(:sync_children)
  end

  it 'memoizes the shared facade' do
    allow(Karya).to receive(:queue_store).and_return(instance_double(Karya::QueueStore::Base))
    allow(Karya::Rails).to receive(:configuration).and_return(:configuration)
    described_class.instance_variable_set(:@facade, nil)
    facade = described_class.send(:facade)

    expect(facade).to be_a(Karya::Internal::FrameworkWorkflow::Facade)
    expect(facade.send(:configuration_provider).call).to eq(:configuration)
  ensure
    described_class.instance_variable_set(:@facade, nil)
  end
end
