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
    definition = described_class.new(id: :invoice_closeout, steps: [calculate_totals, capture_payment])

    expect(definition.steps).to eq([calculate_totals, capture_payment])
    expect(definition.steps).to be_frozen
    expect(definition.dependencies).to contain_exactly(
      have_attributes(step_id: 'capture_payment', depends_on_step_id: 'calculate_totals')
    )
    expect(definition.step(' capture_payment ')).to eq(capture_payment)
    expect(definition).to be_frozen
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
