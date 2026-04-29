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
    expect(catalog.definitions_by_family.keys).to eq(['invoice_closeout'])
    expect(catalog.fetch(' invoice_closeout ')).to eq(definition)
    expect(catalog.resolve(workflow_family: ' invoice_closeout ')).to eq(definition)
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

  it 'resolves explicit versions within one workflow family' do
    default_definition = Karya::Workflow.define(
      :invoice_closeout_v1,
      workflow_family: :invoice_closeout,
      workflow_version: :v1
    ) do
      step :calculate_totals, handler: :calculate_totals
    end
    next_definition = Karya::Workflow.define(
      :invoice_closeout_v2,
      workflow_family: :invoice_closeout,
      workflow_version: :v2,
      default_version: false
    ) do
      step :calculate_totals, handler: :calculate_totals
    end

    catalog = described_class.new(definitions: [default_definition, next_definition])

    expect(catalog.fetch_version(workflow_family: :invoice_closeout, workflow_version: :v1)).to eq(default_definition)
    expect(catalog.fetch_version(workflow_family: :invoice_closeout, workflow_version: :v2)).to eq(next_definition)
    expect(catalog.resolve(workflow_family: :invoice_closeout)).to eq(default_definition)
  end

  it 'rejects duplicate versions within one workflow family' do
    first = Karya::Workflow.define(:invoice_closeout_v1, workflow_family: :invoice_closeout, workflow_version: :v1) do
      step :calculate_totals, handler: :calculate_totals
    end
    duplicate = Karya::Workflow.define(:invoice_closeout_v1_copy, workflow_family: :invoice_closeout, workflow_version: :v1) do
      step :capture_payment, handler: :capture_payment
    end

    expect do
      described_class.new(definitions: [first, duplicate])
    end.to raise_error(
      Karya::Workflow::InvalidDefinitionError,
      'duplicate workflow version "v1" for family "invoice_closeout"'
    )
  end

  it 'rejects multiple default versions within one workflow family' do
    first = Karya::Workflow.define(:invoice_closeout_v1, workflow_family: :invoice_closeout, workflow_version: :v1) do
      step :calculate_totals, handler: :calculate_totals
    end
    second = Karya::Workflow.define(:invoice_closeout_v2, workflow_family: :invoice_closeout, workflow_version: :v2) do
      step :capture_payment, handler: :capture_payment
    end

    expect do
      described_class.new(definitions: [first, second])
    end.to raise_error(
      Karya::Workflow::InvalidDefinitionError,
      'workflow family "invoice_closeout" declares multiple default versions'
    )
  end

  it 'rejects missing family defaults and unknown versions explicitly' do
    first = Karya::Workflow.define(
      :invoice_closeout_v1,
      workflow_family: :invoice_closeout,
      workflow_version: :v1,
      default_version: false
    ) do
      step :calculate_totals, handler: :calculate_totals
    end
    catalog = described_class.new(definitions: [first])

    expect do
      catalog.resolve(workflow_family: :invoice_closeout)
    end.to raise_error(Karya::Workflow::InvalidDefinitionError, 'workflow family "invoice_closeout" has no default version')
    expect do
      catalog.fetch_version(workflow_family: :invoice_closeout, workflow_version: :v2)
    end.to raise_error(
      Karya::Workflow::InvalidDefinitionError,
      'workflow family "invoice_closeout" does not include version "v2"'
    )
    expect do
      catalog.fetch_version(workflow_family: :missing_family, workflow_version: :v1)
    end.to raise_error(
      Karya::Workflow::InvalidDefinitionError,
      'workflow family "missing_family" is not registered'
    )
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
