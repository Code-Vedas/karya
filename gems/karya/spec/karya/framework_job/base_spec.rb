# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::FrameworkJob::Base do
  let(:queue_store) do
    Class.new do
      attr_reader :enqueued_jobs

      def initialize
        @enqueued_jobs = []
      end

      def enqueue(job:, now:)
        @enqueued_jobs << [job, now]
      end
    end.new
  end

  around do |example|
    original_queue_store = Karya.instance_variable_get(:@queue_store)
    Karya.configure_queue_store(queue_store)
    example.run
  ensure
    Karya.configure_queue_store(original_queue_store)
  end

  it 'supports queue and handler declarations with perform_later and perform_now' do
    job_class = Class.new(described_class) do
      queue_as :billing
      karya_handler :billing_sync

      def perform(account_id, force: false)
        [account_id, force]
      end
    end

    expect(job_class.queue_name).to eq('billing')
    expect(job_class.handler_name).to eq('billing_sync')
    expect(job_class.perform_now('acct-1', force: true)).to eq(['acct-1', true])

    enqueued_job = job_class.perform_later('acct-1', force: true)

    expect(enqueued_job.queue).to eq('billing')
    expect(enqueued_job.handler).to eq('billing_sync')
    expect(enqueued_job.arguments).to include('__karya_framework_job_v' => 1)
    expect(queue_store.enqueued_jobs.length).to eq(1)
  end

  it 'defaults queue to default and handler to the class name' do
    stub_const('Karya::FrameworkJobBaseSpecJob', Class.new(described_class) do
      def perform; end
    end)

    expect(Karya::FrameworkJobBaseSpecJob.queue_name).to eq('default')
    expect(Karya::FrameworkJobBaseSpecJob.handler_name).to eq('Karya::FrameworkJobBaseSpecJob')
  end

  it 'returns explicit queue and handler values through the reader methods' do
    job_class = Class.new(described_class) do
      queue_as :billing
      karya_handler :billing_sync

      def perform; end
    end

    expect(job_class.queue_as).to eq('billing')
    expect(job_class.karya_handler).to eq('billing_sync')
  end

  it 'rejects abstract jobs' do
    described_class.abstract
    expect(described_class.abstract?).to be(true)

    expect do
      described_class.perform_later
    end.to raise_error(Karya::InvalidJobAttributeError, /abstract/)
  end

  it 'rejects unnamed jobs without an explicit handler' do
    job_class = Class.new(described_class) do
      def perform; end
    end

    expect do
      job_class.handler_name
    end.to raise_error(Karya::InvalidJobAttributeError, /must have a constant name or explicit karya_handler/)
  end

  it 'treats a nil abstract flag as false' do
    job_class = Class.new(described_class) do
      def perform; end
    end
    job_class.instance_variable_set(:@karya_abstract, nil)

    expect(job_class.abstract?).to be(false)
  end

  it 'supports retry, idempotency, uniqueness, and inherited metadata defaults' do
    parent_job = Class.new(described_class) do
      queue_as :billing
      karya_handler :billing_sync
      retry_with(Karya::RetryPolicy.new(max_attempts: 3, base_delay: 1, multiplier: 2))
      idempotent_by { |account_id| "idempotent-#{account_id}" }
      unique_by(scope: :queued) { |account_id| "unique-#{account_id}" }

      def perform(account_id)
        account_id
      end
    end
    child_job = Class.new(parent_job) do
      karya_handler :billing_sync_child

      def perform(account_id)
        account_id
      end
    end

    built_job = parent_job.build_job(arguments_payload: parent_job.arguments('acct-1').to_payload)

    expect(parent_job.retry_policy).to be_a(Karya::RetryPolicy)
    expect(child_job.default_uniqueness_scope).to eq('queued')
    expect(child_job.send(:inherited_metadata_block, :@karya_uniqueness_block)).to be_a(Proc)
    expect(built_job.idempotency_key).to eq('idempotent-acct-1')
    expect(built_job.uniqueness_key).to eq('unique-acct-1')
  end

  it 'registers subclasses with a nil source path when no external caller location exists' do
    allow(described_class).to receive(:caller_locations).with(1).and_return([])
    allow(Karya::Internal::FrameworkJobRegistry).to receive(:register).and_call_original

    Class.new(described_class)

    expect(Karya::Internal::FrameworkJobRegistry).to have_received(:register).with(
      instance_of(Class),
      source_path: nil
    )
  end

  it 'registers subclasses with the definition path when the caller location has no absolute path' do
    definition_location = instance_double(Thread::Backtrace::Location, path: 'app/jobs/fallback_job.rb', absolute_path: nil)
    allow(described_class).to receive(:caller_locations).with(1).and_return([definition_location])
    allow(Karya::Internal::FrameworkJobRegistry).to receive(:register).and_call_original

    Class.new(described_class)

    expect(Karya::Internal::FrameworkJobRegistry).to have_received(:register).with(
      instance_of(Class),
      source_path: 'app/jobs/fallback_job.rb'
    )
  end

  it 'normalizes non-time timestamps and falls back cleanly when metadata is absent' do
    plain_job = Class.new(described_class) do
      karya_handler :plain_job

      def perform; end
    end

    built_job = plain_job.build_job(arguments_payload: plain_job.arguments.to_payload, now: 1.25)

    expect(built_job.created_at).to eq(Time.at(1.25).utc)
    expect(built_job.idempotency_key).to be_nil
    expect(built_job.uniqueness_key).to be_nil
    expect(plain_job.send(:configured_or_inherited_value, :@missing_value, :missing_reader)).to be_nil
    expect(plain_job.send(:inherited_metadata_block, :@missing_block)).to be_nil
  end

  it 'uses local metadata blocks before inherited ones' do
    parent_job = Class.new(described_class) do
      karya_handler :parent_job
      idempotent_by { 'parent' }

      def perform; end
    end
    child_job = Class.new(parent_job) do
      karya_handler :child_job
      idempotent_by { 'child' }

      def perform; end
    end

    expect(child_job.send(:derive_metadata_value, :@karya_idempotency_block, [], {})).to eq('child')
  end

  it 'falls back to inherited metadata blocks when the subclass does not define one' do
    parent_job = Class.new(described_class) do
      karya_handler :parent_job
      idempotent_by { |account_id| "parent-#{account_id}" }

      def perform; end
    end
    child_job = Class.new(parent_job) do
      karya_handler :child_job

      def perform; end
    end

    expect(child_job.send(:inherited_metadata_block, :@karya_idempotency_block)).to be_a(Proc)
    expect(child_job.send(:derive_metadata_value, :@karya_idempotency_block, ['acct-1'], {})).to eq('parent-acct-1')
    expect(described_class.send(:inherited_metadata_block, :@missing_block)).to be_nil
  end

  it 'rejects missing enqueue blocks' do
    job_class = Class.new(described_class) do
      karya_handler :billing_sync
      def perform; end
    end

    expect { job_class.idempotent_by }.to raise_error(Karya::InvalidJobAttributeError, /requires a block/)
    expect { job_class.unique_by(scope: :account) }.to raise_error(Karya::InvalidJobAttributeError, /requires a block/)
  end
end
