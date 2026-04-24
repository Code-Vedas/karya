# frozen_string_literal: true

RSpec.describe 'Karya::CLI::ConfigBuilder' do
  let(:config_builder_class) { Karya::CLI.const_get(:ConfigBuilder, false) }
  let(:signal_subscription_module) { Karya::CLI.const_get(:SignalSubscription, false) }

  it 'builds supervisor configuration from CLI helpers and options' do
    helpers = {
      normalize_env_prefix_option: ->(_name) { 'KARYA' },
      coerce_optional_positive_integer_option: ->(_name) { 5 },
      resolve_positive_integer_option: lambda do |_name, env_prefix:, defaults:|
        [env_prefix, defaults] == ['KARYA', { 'threads' => 2 }] ? 2 : 1
      end
    }

    configuration = config_builder_class.build(
      options: {
        worker_id: 'worker-1',
        handler: ['billing_sync=String'],
        lease_duration: 30,
        poll_interval: 1,
        stop_when_idle: true
      },
      queues: ['billing'],
      queue_store: :store,
      defaults: { 'threads' => 2 },
      helpers: helpers
    )

    expect(configuration).to include(
      queue_store: :store,
      worker_id: 'worker-1',
      queues: ['billing'],
      lease_duration: 30,
      poll_interval: 1,
      stop_when_idle: true,
      max_iterations: 5,
      processes: 2,
      threads: 2
    )
    expect(configuration.fetch(:signal_subscriber)).to eq(signal_subscription_module.method(:subscribe))
  end
end
