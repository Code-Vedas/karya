# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::WorkflowSupport' do
  subject(:store) { Karya::QueueStore::InMemory.new }

  let(:created_at) { Time.utc(2026, 4, 24, 12, 0, 0) }

  def job(id:, state:)
    Karya::Job.new(id:, queue: :billing, handler: :sync_billing, state:, created_at:)
  end

  it 'treats non-workflow jobs and root workflow jobs as ready' do
    plain_job = job(id: 'job-1', state: :queued)
    root_job = job(id: 'job-2', state: :queued)
    store.send(:state).register_workflow_dependencies('job-2' => [])

    expect(store.send(:workflow_dependencies_satisfied?, plain_job)).to be(true)
    expect(store.send(:workflow_dependencies_satisfied?, root_job)).to be(true)
  end

  it 'requires every prerequisite job to be succeeded' do
    dependent = job(id: 'job-3', state: :queued)
    succeeded = job(id: 'job-1', state: :succeeded)
    queued = job(id: 'job-2', state: :queued)
    store.send(:state).jobs_by_id['job-1'] = succeeded
    store.send(:state).jobs_by_id['job-2'] = queued
    store.send(:state).register_workflow_dependencies('job-3' => %w[job-1 job-2])

    expect(store.send(:workflow_dependencies_satisfied?, dependent)).to be(false)

    store.send(:state).jobs_by_id['job-2'] = job(id: 'job-2', state: :reserved)
    expect(store.send(:workflow_dependencies_satisfied?, dependent)).to be(false)

    store.send(:state).jobs_by_id['job-2'] = job(id: 'job-2', state: :succeeded)
    expect(store.send(:workflow_dependencies_satisfied?, dependent)).to be(true)
  end

  it 'treats missing prerequisite jobs as blocked' do
    dependent = job(id: 'job-2', state: :queued)
    store.send(:state).register_workflow_dependencies('job-2' => ['missing'])

    expect(store.send(:workflow_dependencies_satisfied?, dependent)).to be(false)
  end
end
