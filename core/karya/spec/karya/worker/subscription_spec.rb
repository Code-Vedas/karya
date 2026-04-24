# frozen_string_literal: true

RSpec.describe 'Karya::Worker::Subscription' do
  subject(:subscription) { subscription_class.new(queues: ['billing'], handler_names: [:billing_sync]) }

  let(:subscription_class) { Karya::Worker.const_get(:Subscription, false) }
  let(:job) do
    Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'billing_sync',
      state: :queued,
      created_at: Time.utc(2026, 4, 23, 12, 0, 0)
    )
  end

  it 'normalizes queues and handler names' do
    expect(subscription.queues).to eq(['billing'])
    expect(subscription.handler_names).to eq(['billing_sync'])
  end

  it 'matches jobs by queue and handler' do
    expect(subscription.includes_queue?('billing')).to be(true)
    expect(subscription.handles?('billing_sync')).to be(true)
    expect(subscription.match?(job)).to be(true)
  end
end
