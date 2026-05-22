# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Karya::Internal::DurableQueueStore::WorkflowRuntimeSupport::SnapshotContextBuilder do
  include_context 'with durable queue-store operations spec support'

  let(:helper) { helper_class.new(store:, request: {}) }

  it 'reuses cached snapshots and rejects child-workflow cycles' do
    rows = workflow_enqueue_rows(
      definition: Karya::Workflow.define(:approval) { step :approve, handler: :approve },
      jobs_by_step_id: { approve: job(id: 'job-approve', state: :submission, handler: :approve) },
      batch_id: :helper_batch
    )

    expect(
      described_class.new(
        request: described_class::Request.new(
          host: helper,
          rows:,
          batch_id: 'helper_batch',
          now:,
          cache: { 'helper_batch' => :cached },
          visiting: {}
        )
      ).build
    ).to eq(:cached)

    expect do
      described_class.new(
        request: described_class::Request.new(
          host: helper,
          rows:,
          batch_id: 'helper_batch',
          now:,
          cache: {},
          visiting: { 'helper_batch' => true }
        )
      ).build
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /child workflow cycle detected/)
  end

  it 'raises when a workflow batch member job is missing' do
    rows = workflow_enqueue_rows(
      definition: Karya::Workflow.define(:approval) { step :approve, handler: :approve },
      jobs_by_step_id: { approve: job(id: 'job-approve', state: :submission, handler: :approve) },
      batch_id: :helper_batch
    )

    expect do
      described_class.new(
        request: described_class::Request.new(
          host: helper,
          rows: rows.merge(jobs: []),
          batch_id: 'helper_batch',
          now:,
          cache: {},
          visiting: {}
        )
      ).build
    end.to raise_error(Karya::Workflow::InvalidExecutionError, /member job .* is not registered/)
  end
end
