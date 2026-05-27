# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::CLI do
  let(:signal_subscription_class) { described_class.const_get(:SignalSubscription, false) }

  describe 'SignalSubscription' do
    it 'subscribes and restores process signal handlers' do
      previous_handlers = { 'TERM' => 'DEFAULT' }

      allow(Signal).to receive(:trap) do |signal, command = nil, &block|
        if block
          old_handler = previous_handlers.fetch(signal, 'DEFAULT')
          previous_handlers[signal] = block
          old_handler
        else
          previous_handlers[signal] = command
        end
      end

      handler = instance_spy(Proc)
      restore = signal_subscription_class.subscribe('TERM', handler)
      previous_handlers.fetch('TERM').call
      restore.call

      expect(handler).to have_received(:call)
      expect(Signal).to have_received(:trap).with('TERM')
      expect(Signal).to have_received(:trap).with('TERM', 'DEFAULT')
    end
  end
end
