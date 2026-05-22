# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::Worker::HandlerRegistry' do
  let(:handler_registry_class) { Karya::Worker.const_get(:HandlerRegistry, false) }
  let(:handler) { -> {} }

  it 'normalizes handler names and exposes them as names' do
    registry = handler_registry_class.new({ billing_sync: handler })

    expect(registry.names).to eq(['billing_sync'])
  end

  it 'raises a missing handler error for unknown names' do
    registry = handler_registry_class.new({ billing_sync: handler })

    expect do
      registry.fetch('missing')
    end.to raise_error(Karya::MissingHandlerError, 'handler "missing" is not registered')
  end
end
