# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::CLI::HandlerParser' do
  let(:handler_parser_class) { Karya::CLI.const_get(:HandlerParser, false) }

  it 'parses handler entries into a mapping' do
    mapping = handler_parser_class.parse(['billing_sync=String'])

    expect(mapping).to eq({ 'billing_sync' => String })
  end
end
