# frozen_string_literal: true

RSpec.describe 'Karya::CLI::HandlerParser' do
  let(:handler_parser_class) { Karya::CLI.const_get(:HandlerParser, false) }

  it 'parses handler entries into a mapping' do
    mapping = handler_parser_class.parse(['billing_sync=String'])

    expect(mapping).to eq({ 'billing_sync' => String })
  end
end
