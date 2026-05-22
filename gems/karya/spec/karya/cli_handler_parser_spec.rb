# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::CLI do
  let(:handler_parser_class) { described_class.const_get(:HandlerParser, false) }

  describe 'HandlerParser' do
    it 'rejects handler entries without NAME=CONSTANT format' do
      expect do
        handler_parser_class.parse(['billing_sync'])
      end.to raise_error(Thor::Error, /NAME=CONSTANT/)
    end

    it 'rejects handler constants that cannot be resolved' do
      expect do
        handler_parser_class.parse(['billing_sync=MissingCliWorkerHandler'])
      end.to raise_error(Thor::Error, /could not resolve handler constant/)
    end

    it 'rejects duplicate handler names' do
      stub_const('BillingSyncOne', Class.new)
      stub_const('BillingSyncTwo', Class.new)

      expect do
        handler_parser_class.parse(['billing_sync=BillingSyncOne', 'billing_sync=BillingSyncTwo'])
      end.to raise_error(Thor::Error, /duplicate handler mapping for "billing_sync"/)
    end
  end
end
