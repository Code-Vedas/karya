# frozen_string_literal: true

RSpec.describe 'Karya::CLI::MappingEntry' do
  let(:mapping_entry_class) { Karya::CLI.const_get(:MappingEntry, false) }

  it 'parses the name and constant name from one entry' do
    entry = mapping_entry_class.new('billing_sync=String')

    expect(entry.name).to eq('billing_sync')
    expect(entry.constant_name).to eq('String')
  end

  it 'merges a resolved handler constant into the target hash' do
    handlers = {}

    mapping_entry_class.new('billing_sync=String').merge_into(handlers)

    expect(handlers).to eq({ 'billing_sync' => String })
  end
end
