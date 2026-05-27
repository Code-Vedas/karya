# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::ActiveJob do
  let(:queue_store) { instance_double(Karya::QueueStore::Base, enqueue: nil) }

  before do
    Karya.configure_queue_store(queue_store)
  end

  after do
    Karya.configure_queue_store(nil)
  end

  it 'exposes the handler contract' do
    expect(described_class.handler_name).to eq('active_job')
    expect(described_class.handler).to respond_to(:call)
  end

  it 'returns a queue adapter when ActiveJob support can be loaded' do
    allow(Karya::Internal::ActiveJobLoader).to receive(:require!).and_return(true)

    expect(described_class.queue_adapter).to be_a(described_class::QueueAdapter)
  end

  it 'raises a load error when the activejob gem is unavailable' do
    expect do
      described_class.queue_adapter
    end.to raise_error(LoadError, /cannot load active_job/)
  end

  it 'enqueues serialized ActiveJob payloads through Karya' do
    stub_const('ActiveJobLike', Class.new)
    job = instance_double(
      ActiveJobLike,
      job_id: 'active-job-1',
      queue_name: 'default',
      serialize: { 'job_class' => 'DemoActiveJob', 'arguments' => ['hello'] }
    )

    described_class::QueueAdapter.new.enqueue(job)

    expect(queue_store).to have_received(:enqueue) do |job:, now:|
      expect(job.queue).to eq('default')
      expect(job.handler).to eq('active_job')
      expect(job.arguments.fetch('job_data')).to include('job_class' => 'DemoActiveJob')
      expect(now).to be_a(Time)
    end
  end

  it 'marks after-commit enqueue as unsupported' do
    expect(described_class::QueueAdapter.new.enqueue_after_transaction_commit?).to be(false)
  end

  it 'delegates scheduled ActiveJob enqueue through Karya.enqueue_at' do
    stub_const('ActiveJobLike', Class.new)
    scheduled_at = Time.utc(2026, 5, 21, 13, 0, 0)
    job = instance_double(
      ActiveJobLike,
      job_id: 'active-job-2',
      queue_name: 'default',
      serialize: { 'job_class' => 'DemoActiveJob', 'arguments' => ['later'] }
    )
    allow(Karya).to receive(:enqueue_at).and_return(
      {
        job_id: 'active-job-2',
        job_class: 'Karya::Internal::DelayedEnqueueJob',
        args: ['payload'],
        queue: nil,
        run_at: scheduled_at,
        created_at: Time.utc(2026, 5, 21, 12, 0, 0)
      }
    )
    allow(Karya::Hooks).to receive(:dispatch)

    described_class::QueueAdapter.new.enqueue_at(job, scheduled_at.to_f)

    expect(Karya).to have_received(:enqueue_at).with(
      queue: 'default',
      handler: 'active_job',
      arguments: { 'job_data' => { 'job_class' => 'DemoActiveJob', 'arguments' => ['later'] } },
      at: scheduled_at,
      now: be_a(Time),
      job_id: 'active-job-2'
    )
    expect(Karya::Hooks).to have_received(:dispatch).with(
      'active_job_enqueue',
      payload: {
        'job_id' => 'active-job-2',
        'queue' => 'default',
        'handler' => 'active_job',
        'scheduled_at' => '2026-05-21T13:00:00Z'
      }
    )
  end

  it 'includes scheduled_at in hook payloads when one is provided' do
    stub_const('ActiveJobLike', Class.new)
    scheduled_at = Time.utc(2026, 5, 21, 12, 0, 0)
    job = instance_double(ActiveJobLike, job_id: 'job-1', queue_name: 'default')

    payload = described_class::QueueAdapter.send(:hook_payload_for, job:, scheduled_at:)

    expect(payload).to include(
      'job_id' => 'job-1',
      'queue' => 'default',
      'handler' => 'active_job',
      'scheduled_at' => '2026-05-21T12:00:00Z'
    )
  end

  it 'dispatches ActiveJob execution through ActiveJob::Base' do
    stub_const('ActiveJob::Base', Class.new)
    active_job_base = class_double(ActiveJob::Base, execute: nil)
    stub_const('ActiveJob::Base', active_job_base)
    allow(Karya::Internal::ActiveJobLoader).to receive(:require!).and_return(true)
    allow(Karya::Hooks).to receive(:dispatch)

    described_class.handler.call(job_data: { 'job_class' => 'DemoActiveJob' })

    expect(Karya::Hooks).to have_received(:dispatch).with(
      'active_job_execute',
      payload: { 'job_data' => { 'job_class' => 'DemoActiveJob' } }
    )
    expect(active_job_base).to have_received(:execute).with('job_class' => 'DemoActiveJob')
  end
end
