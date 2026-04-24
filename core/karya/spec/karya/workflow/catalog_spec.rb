# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Workflow::Catalog do
  let(:definition) do
    Karya::Workflow.define(:invoice_closeout) do
      step :calculate_totals, handler: :calculate_totals
    end
  end

  it 'indexes workflow definitions by normalized id' do
    catalog = described_class.new(definitions: [definition])

    expect(catalog.definitions.keys).to eq(['invoice_closeout'])
    expect(catalog.fetch(' invoice_closeout ')).to eq(definition)
    expect(catalog).to be_frozen
  end

  it 'raises a workflow domain error for unknown workflow ids' do
    catalog = described_class.new(definitions: [definition])

    expect do
      catalog.fetch(:missing)
    end.to raise_error(Karya::Workflow::InvalidDefinitionError, 'workflow "missing" is not registered')
  end

  it 'rejects duplicate workflow ids' do
    duplicate_definition = Karya::Workflow.define(' invoice_closeout ') do
      step :capture_payment, handler: :capture_payment
    end

    expect do
      described_class.new(definitions: [definition, duplicate_definition])
    end.to raise_error(Karya::Workflow::InvalidDefinitionError, 'duplicate workflow id "invoice_closeout"')
  end

  it 'rejects non-array definition collections' do
    expect do
      described_class.new(definitions: definition)
    end.to raise_error(
      Karya::Workflow::InvalidDefinitionError,
      'definitions must be an Array of Karya::Workflow::Definition'
    )
  end

  it 'rejects non-definition members inside the catalog' do
    expect do
      described_class.new(definitions: [definition, :invoice_closeout])
    end.to raise_error(
      Karya::Workflow::InvalidDefinitionError,
      'definitions must be Karya::Workflow::Definition instances'
    )
  end
end
