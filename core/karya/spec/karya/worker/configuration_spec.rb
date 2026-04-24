# frozen_string_literal: true

RSpec.describe 'Karya::Worker::Configuration' do
  let(:configuration_class) { Karya::Worker.const_get(:Configuration, false) }
  let(:handler) { -> {} }

  it 'extracts known options from a mutable options hash' do
    options = {
      worker_id: 'worker-1',
      queues: ['billing'],
      handlers: { 'billing_sync' => handler },
      lease_duration: 30,
      extra: true
    }

    configuration = configuration_class.from_options(options)

    expect(configuration.worker_id).to eq('worker-1')
    expect(options).to eq({ extra: true })
  end

  it 'builds a normalized subscription from queues and handlers' do
    configuration = configuration_class.new(
      worker_id: 'worker-1',
      queues: ['billing'],
      handlers: { billing_sync: handler },
      lease_duration: 30
    )

    expect(configuration.subscription.queues).to eq(['billing'])
    expect(configuration.subscription.handler_names).to eq(['billing_sync'])
  end
end
