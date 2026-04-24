# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::Workflow::ExecutionBinding' do
  let(:described_class) { Karya::Workflow.const_get(:ExecutionBinding, false) }
  let(:created_at) { Time.utc(2026, 4, 24, 12, 0, 0) }
  let(:definition) do
    Karya::Workflow.define(:invoice_closeout) do
      step :calculate_totals, handler: :calculate_totals, arguments: { account_id: 'acct-1' }
      step :capture_payment, handler: :capture_payment, depends_on: :calculate_totals
      step :emit_receipt, handler: :emit_receipt, depends_on: %i[calculate_totals capture_payment]
    end
  end

  def submission_job(id:, handler:, arguments: {})
    Karya::Job.new(id:, queue: :billing, handler:, arguments:, state: :submission, created_at:)
  end

  def compensation_job(id:, handler:, arguments: {})
    Karya::Job.new(id:, queue: :rollback, handler:, arguments:, state: :submission, created_at:)
  end

  def jobs_by_step_id
    {
      ' calculate_totals ' => submission_job(
        id: 'job-1',
        handler: :calculate_totals,
        arguments: { account_id: 'acct-1' }
      ),
      capture_payment: submission_job(id: 'job-2', handler: :capture_payment),
      emit_receipt: submission_job(id: 'job-3', handler: :emit_receipt)
    }
  end

  it 'binds normalized workflow step ids to concrete jobs' do
    binding = described_class.new(definition:, jobs_by_step_id:, batch_id: ' batch-1 ')

    expect(binding.batch_id).to eq('batch-1')
    expect(binding.jobs.map(&:id)).to eq(%w[job-1 job-2 job-3])
    expect(binding.dependency_job_ids_by_job_id).to eq(
      'job-1' => [],
      'job-2' => ['job-1'],
      'job-3' => %w[job-1 job-2]
    )
    expect(binding).to be_frozen
    expect(binding.jobs).to be_frozen
  end

  it 'binds compensation jobs for compensable workflow steps' do
    definition = Karya::Workflow.define(:refund_invoice) do
      step :capture_payment,
           handler: :capture_payment,
           compensate_with: :refund_payment,
           compensation_arguments: { reason: :workflow_rollback }
    end
    binding = described_class.new(
      definition:,
      jobs_by_step_id: { capture_payment: submission_job(id: 'job-1', handler: :capture_payment) },
      compensation_jobs_by_step_id: {
        ' capture_payment ' => compensation_job(
          id: 'rollback-job-1',
          handler: :refund_payment,
          arguments: { reason: :workflow_rollback }
        )
      },
      batch_id: 'batch-1'
    )

    expect(binding.compensation_jobs_by_step_id.keys).to eq(['capture_payment'])
    expect(binding.compensation_jobs_by_step_id.fetch('capture_payment').id).to eq('rollback-job-1')
    expect(binding.compensation_jobs_by_step_id).to be_frozen
  end

  it 'rejects non-definition input' do
    expect do
      described_class.new(definition: :invoice_closeout, jobs_by_step_id:, batch_id: 'batch-1')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'definition must be a Karya::Workflow::Definition')
  end

  it 'rejects non-hash job maps' do
    expect do
      described_class.new(definition:, jobs_by_step_id: [['calculate_totals']], batch_id: 'batch-1')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'jobs_by_step_id must be a Hash')
  end

  it 'rejects duplicate-normalized step ids' do
    duplicate_jobs = jobs_by_step_id.merge(calculate_totals: submission_job(id: 'job-4', handler: :calculate_totals))

    expect do
      described_class.new(definition:, jobs_by_step_id: duplicate_jobs, batch_id: 'batch-1')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'duplicate workflow step job "calculate_totals"')
  end

  it 'rejects missing and unknown step ids' do
    expect do
      described_class.new(definition:, jobs_by_step_id: jobs_by_step_id.except(:emit_receipt), batch_id: 'batch-1')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'missing workflow step job "emit_receipt"')

    expect do
      described_class.new(
        definition:,
        jobs_by_step_id: jobs_by_step_id.merge(extra: submission_job(id: 'job-4', handler: :extra)),
        batch_id: 'batch-1'
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'unknown workflow step job "extra"')
  end

  it 'rejects non-job values and non-submission jobs' do
    expect do
      described_class.new(definition:, jobs_by_step_id: jobs_by_step_id.merge(capture_payment: 'job-2'), batch_id: 'batch-1')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'workflow step "capture_payment" job must be a Karya::Job')

    queued_job = submission_job(id: 'job-2', handler: :capture_payment).transition_to(:queued, updated_at: created_at + 1)
    expect do
      described_class.new(definition:, jobs_by_step_id: jobs_by_step_id.merge(capture_payment: queued_job), batch_id: 'batch-1')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'workflow step "capture_payment" job must be in :submission state')
  end

  it 'rejects handler and argument mismatches' do
    expect do
      described_class.new(
        definition:,
        jobs_by_step_id: jobs_by_step_id.merge(capture_payment: submission_job(id: 'job-2', handler: :wrong)),
        batch_id: 'batch-1'
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'workflow step "capture_payment" job handler must match workflow step handler')

    expect do
      described_class.new(
        definition:,
        jobs_by_step_id: jobs_by_step_id.merge(
          ' calculate_totals ' => submission_job(id: 'job-1', handler: :calculate_totals, arguments: { account_id: 'acct-2' })
        ),
        batch_id: 'batch-1'
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'workflow step "calculate_totals" job arguments must match workflow step arguments')
  end

  it 'rejects missing and unknown compensation job bindings' do
    definition = Karya::Workflow.define(:refund_invoice) do
      step :capture_payment,
           handler: :capture_payment,
           compensate_with: :refund_payment,
           compensation_arguments: { reason: :workflow_rollback }
    end
    primary_jobs = { capture_payment: submission_job(id: 'job-1', handler: :capture_payment) }

    expect do
      described_class.new(definition:, jobs_by_step_id: primary_jobs, compensation_jobs_by_step_id: {}, batch_id: 'batch-1')
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'missing workflow compensation job "capture_payment"')

    expect do
      described_class.new(
        definition:,
        jobs_by_step_id: primary_jobs,
        compensation_jobs_by_step_id: { extra: compensation_job(id: 'rollback-job-1', handler: :refund_payment) },
        batch_id: 'batch-1'
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'missing workflow compensation job "capture_payment"')

    expect do
      described_class.new(
        definition:,
        jobs_by_step_id: primary_jobs,
        compensation_jobs_by_step_id: {
          capture_payment: compensation_job(id: 'rollback-job-1', handler: :refund_payment, arguments: { reason: :workflow_rollback }),
          extra: compensation_job(id: 'rollback-job-2', handler: :refund_payment)
        },
        batch_id: 'batch-1'
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'unknown workflow compensation job "extra"')
  end

  it 'rejects invalid compensation job values' do
    definition = Karya::Workflow.define(:refund_invoice) do
      step :capture_payment,
           handler: :capture_payment,
           compensate_with: :refund_payment,
           compensation_arguments: { reason: :workflow_rollback }
    end
    primary_jobs = { capture_payment: submission_job(id: 'job-1', handler: :capture_payment) }

    expect do
      described_class.new(
        definition:,
        jobs_by_step_id: primary_jobs,
        compensation_jobs_by_step_id: { capture_payment: 'rollback-job-1' },
        batch_id: 'batch-1'
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'workflow compensation "capture_payment" job must be a Karya::Job')

    queued_job = compensation_job(id: 'rollback-job-1', handler: :refund_payment).transition_to(:queued, updated_at: created_at + 1)
    expect do
      described_class.new(
        definition:,
        jobs_by_step_id: primary_jobs,
        compensation_jobs_by_step_id: { capture_payment: queued_job },
        batch_id: 'batch-1'
      )
    end.to raise_error(Karya::Workflow::InvalidExecutionError, 'workflow compensation "capture_payment" job must be in :submission state')

    expect do
      described_class.new(
        definition:,
        jobs_by_step_id: primary_jobs,
        compensation_jobs_by_step_id: { capture_payment: compensation_job(id: 'rollback-job-1', handler: :wrong) },
        batch_id: 'batch-1'
      )
    end.to raise_error(
      Karya::Workflow::InvalidExecutionError,
      'workflow compensation "capture_payment" job handler must match workflow compensation handler'
    )

    expect do
      described_class.new(
        definition:,
        jobs_by_step_id: primary_jobs,
        compensation_jobs_by_step_id: {
          capture_payment: compensation_job(
            id: 'rollback-job-1',
            handler: :refund_payment,
            arguments: { reason: :manual_rollback }
          )
        },
        batch_id: 'batch-1'
      )
    end.to raise_error(
      Karya::Workflow::InvalidExecutionError,
      'workflow compensation "capture_payment" job arguments must match workflow compensation arguments'
    )
  end
end
