# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Workflow::Step do
  it 'normalizes ids, handler, arguments, and dependencies' do
    step = described_class.new(
      id: ' emit_receipt ',
      handler: :emit_receipt,
      arguments: { receipt: { mode: :email }, 'count' => 1 },
      depends_on: [' capture_payment ', :calculate_totals]
    )

    expect(step.id).to eq('emit_receipt')
    expect(step.handler).to eq('emit_receipt')
    expect(step.arguments).to eq({ 'receipt' => { 'mode' => :email }, 'count' => 1 })
    expect(step.arguments).to be_frozen
    expect(step.arguments.fetch('receipt')).to be_frozen
    expect(step.depends_on).to eq(%w[capture_payment calculate_totals])
    expect(step.depends_on).to be_frozen
    expect(step).to be_frozen
  end

  it 'normalizes optional compensation metadata' do
    step = described_class.new(
      id: :capture_payment,
      handler: :capture_payment,
      compensate_with: ' refund_payment ',
      compensation_arguments: { reason: :workflow_rollback }
    )

    expect(step.compensable?).to be(true)
    expect(step.compensate_with).to eq('refund_payment')
    expect(step.compensation_arguments).to eq('reason' => :workflow_rollback)
    expect(step.compensation_arguments).to be_frozen
  end

  it 'defaults compensation metadata to no-op rollback behavior' do
    step = described_class.new(id: :capture_payment, handler: :capture_payment)

    expect(step.compensable?).to be(false)
    expect(step.compensate_with).to be_nil
    expect(step.compensation_arguments).to eq({})
  end

  it 'rejects invalid compensation arguments' do
    expect do
      described_class.new(id: :capture_payment, handler: :capture_payment, compensation_arguments: [])
    end.to raise_error(
      Karya::Workflow::InvalidDefinitionError,
      'workflow step "capture_payment" (handler "compensation") has invalid arguments: arguments must be a Hash'
    )
  end

  it 'rejects compensation arguments without a compensation handler' do
    expect do
      described_class.new(
        id: :capture_payment,
        handler: :capture_payment,
        compensation_arguments: { reason: :workflow_rollback }
      )
    end.to raise_error(
      Karya::Workflow::InvalidDefinitionError,
      'workflow step "capture_payment" cannot define compensation_arguments without compensate_with'
    )
  end

  it 'rejects unknown step options' do
    expect do
      described_class.new(id: :capture_payment, handler: :capture_payment, unknown: true)
    end.to raise_error(ArgumentError, 'unknown keyword: :unknown')
  end

  it 'reports every unknown step option' do
    expect do
      described_class.new(id: :capture_payment, handler: :capture_payment, unknown: true, extra: true)
    end.to raise_error(ArgumentError, 'unknown keywords: :unknown, :extra')
  end

  it 'rejects duplicate dependency ids after normalization' do
    expect do
      described_class.new(id: :emit_receipt, handler: :emit_receipt, depends_on: [:calculate_totals, ' calculate_totals '])
    end.to raise_error(
      Karya::Workflow::InvalidDefinitionError,
      'duplicate depends_on step "calculate_totals" after normalization'
    )
  end

  it 'rejects invalid argument types' do
    expect do
      described_class.new(id: :emit_receipt, handler: :emit_receipt, arguments: { receipt: Object.new })
    end.to raise_error(
      Karya::Workflow::InvalidDefinitionError,
      'workflow step "emit_receipt" (handler "emit_receipt") has invalid arguments: ' \
      'argument values must be composed of Hash, Array, String, Time, Symbol, Numeric, boolean, or nil'
    )
  end

  it 'rejects non-hash arguments' do
    expect do
      described_class.new(id: :emit_receipt, handler: :emit_receipt, arguments: [])
    end.to raise_error(
      Karya::Workflow::InvalidDefinitionError,
      'workflow step "emit_receipt" (handler "emit_receipt") has invalid arguments: arguments must be a Hash'
    )
  end

  it 'rejects duplicate argument keys after normalization' do
    expect do
      described_class.new(id: :emit_receipt, handler: :emit_receipt, arguments: { receipt: 1, ' receipt ' => 2 })
    end.to raise_error(
      Karya::Workflow::InvalidDefinitionError,
      'workflow step "emit_receipt" (handler "emit_receipt") has invalid arguments: ' \
      'duplicate argument key after normalization: "receipt"'
    )
  end

  it 'rejects blank argument keys after normalization' do
    expect do
      described_class.new(id: :emit_receipt, handler: :emit_receipt, arguments: { '   ' => 1 })
    end.to raise_error(
      Karya::Workflow::InvalidDefinitionError,
      'workflow step "emit_receipt" (handler "emit_receipt") has invalid arguments: argument keys must be present'
    )
  end

  it 'normalizes nested arrays in arguments' do
    step = described_class.new(
      id: :emit_receipt,
      handler: :emit_receipt,
      arguments: { recipients: [{ address: 'a@example.com' }] }
    )

    expect(step.arguments.fetch('recipients')).to eq([{ 'address' => 'a@example.com' }])
    expect(step.arguments.fetch('recipients')).to be_frozen
    expect(step.arguments.fetch('recipients').first).to be_frozen
  end

  it 'rejects recursive argument structures' do
    recursive = {}
    recursive[:self] = recursive

    expect do
      described_class.new(id: :emit_receipt, handler: :emit_receipt, arguments: recursive)
    end.to raise_error(
      Karya::Workflow::InvalidDefinitionError,
      'workflow step "emit_receipt" (handler "emit_receipt") has invalid arguments: ' \
      'arguments must not contain recursive structures'
    )
  end
end
