# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../../lib/karya/internal/bulk_mutation'

RSpec.describe Karya::Internal::BulkMutation do
  let(:requested_job_ids_class) { described_class.const_get(:RequestedJobIds, false) }
  let(:skipped_job_class) { described_class.const_get(:SkippedJob, false) }
  let(:report_builder_class) { described_class.const_get(:ReportBuilder, false) }
  let(:now) { Time.utc(2026, 4, 23, 12, 0, 0) }

  it 'marks duplicate requested job ids while iterating' do
    requested_job_ids = requested_job_ids_class.new(%w[job-1 job-2 job-1])
    yielded = requested_job_ids.enum_for(:each).map { |job_id, duplicate_request| [job_id, duplicate_request] }

    expect(yielded).to eq(
      [
        ['job-1', false],
        ['job-2', false],
        ['job-1', true]
      ]
    )
  end

  it 'builds frozen skipped-job hashes' do
    skipped_job = skipped_job_class.new(job_id: 'job-1', reason: :not_found, state: nil).to_h

    expect(skipped_job).to eq(job_id: 'job-1', reason: :not_found, state: nil)
    expect(skipped_job).to be_frozen
  end

  it 'builds bulk mutation reports and records duplicate requests as skipped' do
    changed_job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'billing_sync',
      state: :queued,
      created_at: now,
      updated_at: now
    )

    report = report_builder_class.new(action: :retry_jobs, job_ids: %w[job-1 job-1 missing], now:).to_report do |job_id, changed_jobs, skipped_jobs|
      if job_id == 'job-1'
        changed_jobs << changed_job
      else
        skipped_jobs << skipped_job_class.new(job_id:, reason: :not_found).to_h
      end
    end

    expect(report.action).to eq(:retry_jobs)
    expect(report.performed_at).to eq(now)
    expect(report.requested_job_ids).to eq(%w[job-1 job-1 missing])
    expect(report.changed_jobs).to eq([changed_job])
    expect(report.skipped_jobs).to eq(
      [
        { job_id: 'job-1', reason: :duplicate_request, state: nil },
        { job_id: 'missing', reason: :not_found, state: nil }
      ]
    )
  end
end
