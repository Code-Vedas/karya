# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::QueueStore::InMemory::Internal::ExpirationSupport' do
  subject(:store) { store_class.new }

  let(:store_class) { Karya::QueueStore::InMemory }
  let(:expiring_job_class) do
    store_class.const_get(:Internal, false)
               .const_get(:ExpirationSupport, false)
               .const_get(:ExpiringJob, false)
  end
  let(:created_at) { Time.utc(2026, 3, 27, 12, 0, 0) }

  it 'detects job expiry from expires_at' do
    job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'billing_sync',
      state: :queued,
      created_at:,
      updated_at: created_at + 1,
      expires_at: created_at + 2
    )

    expiring_job = expiring_job_class.new(job)

    expect(expiring_job.expired?(created_at + 3)).to be(true)
  end

  it 'builds expired jobs through the lifecycle helper' do
    job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'billing_sync',
      state: :queued,
      created_at:,
      updated_at: created_at + 1,
      expires_at: created_at + 2
    )

    expired_job = expiring_job_class.new(job).to_failed_job(created_at + 3)

    expect(expired_job.state).to eq(:failed)
    expect(expired_job.failure_classification).to eq(:expired)
  end
end
