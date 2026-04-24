# frozen_string_literal: true

RSpec.describe 'Karya::CLI::SignalSubscription' do
  let(:signal_subscription_module) { Karya::CLI.const_get(:SignalSubscription, false) }

  it 'restores the previous signal handler when unsubscribed' do
    previous_handler = proc {}
    allow(Signal).to receive(:trap).with('TERM').and_return(previous_handler)
    allow(Signal).to receive(:trap).with('TERM', previous_handler)

    restore = signal_subscription_module.subscribe('TERM', -> {})
    restore.call

    expect(Signal).to have_received(:trap).with('TERM')
    expect(Signal).to have_received(:trap).with('TERM', previous_handler)
  end
end
