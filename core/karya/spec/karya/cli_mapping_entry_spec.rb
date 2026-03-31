# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::CLI do
  let(:mapping_entry_class) { described_class.const_get(:MappingEntry, false) }

  describe 'MappingEntry' do
    describe '#name' do
      it 'extracts the name from a NAME=CONSTANT entry' do
        entry = mapping_entry_class.new('billing_sync=BillingSyncHandler')

        expect(entry.name).to eq('billing_sync')
      end

      it 'strips whitespace from the name' do
        entry = mapping_entry_class.new('  billing_sync  =BillingSyncHandler')

        expect(entry.name).to eq('billing_sync')
      end
    end

    describe '#constant_name' do
      it 'extracts the constant name from a NAME=CONSTANT entry' do
        entry = mapping_entry_class.new('billing_sync=BillingSyncHandler')

        expect(entry.constant_name).to eq('BillingSyncHandler')
      end

      it 'strips whitespace from the constant name' do
        entry = mapping_entry_class.new('billing_sync=  BillingSyncHandler  ')

        expect(entry.constant_name).to eq('BillingSyncHandler')
      end
    end

    describe '#merge_into' do
      it 'merges the handler into the provided hash' do
        stub_const('TestHandler', Class.new)
        entry = mapping_entry_class.new('test_handler=TestHandler')
        handlers = {}

        entry.merge_into(handlers)

        expect(handlers['test_handler']).to eq(TestHandler)
      end

      it 'raises Thor::Error when the constant cannot be resolved' do
        entry = mapping_entry_class.new('test_handler=NonExistentHandler')
        handlers = {}

        expect do
          entry.merge_into(handlers)
        end.to raise_error(Thor::Error, /could not resolve handler constant/)
      end
    end

    it 'rejects entries without NAME=CONSTANT format' do
      expect do
        mapping_entry_class.new('billing_sync').name
      end.to raise_error(Thor::Error, /NAME=CONSTANT/)
    end

    it 'rejects entries with empty name' do
      expect do
        mapping_entry_class.new('=BillingSyncHandler').name
      end.to raise_error(Thor::Error, /NAME=CONSTANT/)
    end

    it 'rejects entries with empty constant name' do
      expect do
        mapping_entry_class.new('billing_sync=').name
      end.to raise_error(Thor::Error, /NAME=CONSTANT/)
    end
  end
end
