# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Workflow::Definition do
  let(:calculate_totals) { Karya::Workflow::Step.new(id: :calculate_totals, handler: :calculate_totals) }
  let(:capture_payment) do
    Karya::Workflow::Step.new(id: :capture_payment, handler: :capture_payment, depends_on: :calculate_totals)
  end

  it 'keeps steps ordered and exposes step lookup by normalized id' do
    emit_receipt = Karya::Workflow::Step.new(
      id: :emit_receipt,
      handler: :emit_receipt,
      depends_on: :capture_payment,
      compensate_with: :void_receipt
    )
    definition = described_class.new(id: :invoice_closeout, steps: [calculate_totals, capture_payment, emit_receipt])

    expect(definition.steps).to eq([calculate_totals, capture_payment, emit_receipt])
    expect(definition.steps).to be_frozen
    expect(definition.step_ids).to eq(%w[calculate_totals capture_payment emit_receipt])
    expect(definition.step_ids).to be_frozen
    expect(definition.dependencies).to contain_exactly(
      have_attributes(step_id: 'capture_payment', depends_on_step_id: 'calculate_totals'),
      have_attributes(step_id: 'emit_receipt', depends_on_step_id: 'capture_payment')
    )
    expect(definition.step(' capture_payment ')).to eq(capture_payment)
    expect(definition.fetch_step(' emit_receipt ')).to eq(emit_receipt)
    expect(definition.dependencies_for(:emit_receipt)).to eq(['capture_payment'])
    expect(definition.dependents_for(:calculate_totals)).to eq(['capture_payment'])
    expect(definition.root_step_ids).to eq(['calculate_totals'])
    expect(definition.leaf_step_ids).to eq(['emit_receipt'])
    expect(definition.compensable_step_ids).to eq(['emit_receipt'])
    expect(definition).to be_frozen
  end

  it 'raises definition errors when fetching unknown step inspection' do
    definition = described_class.new(id: :invoice_closeout, steps: [calculate_totals])

    expect(definition.step(:missing)).to be_nil
    expect do
      definition.fetch_step(:missing)
    end.to raise_error(Karya::Workflow::InvalidDefinitionError, 'unknown workflow step "missing"')
    expect do
      definition.dependencies_for(:missing)
    end.to raise_error(Karya::Workflow::InvalidDefinitionError, 'unknown workflow step "missing"')
    expect do
      definition.dependents_for(:missing)
    end.to raise_error(Karya::Workflow::InvalidDefinitionError, 'unknown workflow step "missing"')
  end

  it 'rejects duplicate step ids' do
    duplicate_step = Karya::Workflow::Step.new(id: ' calculate_totals ', handler: :other)

    expect do
      described_class.new(id: :invoice_closeout, steps: [calculate_totals, duplicate_step])
    end.to raise_error(Karya::Workflow::InvalidDefinitionError, 'duplicate step id "calculate_totals"')
  end

  it 'rejects unknown dependency targets' do
    unknown_dependency = Karya::Workflow::Step.new(id: :emit_receipt, handler: :emit_receipt, depends_on: :missing)

    expect do
      described_class.new(id: :invoice_closeout, steps: [calculate_totals, unknown_dependency])
    end.to raise_error(
      Karya::Workflow::InvalidDefinitionError,
      'step "emit_receipt" depends on unknown step "missing"'
    )
  end

  it 'rejects self dependencies' do
    self_dependency = Karya::Workflow::Step.new(id: :emit_receipt, handler: :emit_receipt, depends_on: :emit_receipt)

    expect do
      described_class.new(id: :invoice_closeout, steps: [calculate_totals, self_dependency])
    end.to raise_error(
      Karya::Workflow::InvalidDefinitionError,
      'step "emit_receipt" must not depend on itself'
    )
  end

  it 'rejects dependency cycles' do
    first = Karya::Workflow::Step.new(id: :first, handler: :first, depends_on: :second)
    second = Karya::Workflow::Step.new(id: :second, handler: :second, depends_on: :first)

    expect do
      described_class.new(id: :cyclic, steps: [first, second])
    end.to raise_error(
      Karya::Workflow::InvalidDefinitionError,
      'workflow dependency cycle detected at "first"'
    )
  end

  it 'rejects non-array step collections' do
    expect do
      described_class.new(id: :invoice_closeout, steps: calculate_totals)
    end.to raise_error(
      Karya::Workflow::InvalidDefinitionError,
      'steps must be an Array of Karya::Workflow::Step'
    )
  end

  it 'rejects non-step members inside the step collection' do
    expect do
      described_class.new(id: :invoice_closeout, steps: [calculate_totals, :capture_payment])
    end.to raise_error(
      Karya::Workflow::InvalidDefinitionError,
      'steps must be Karya::Workflow::Step instances'
    )
  end
end
