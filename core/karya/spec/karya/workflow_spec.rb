# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Workflow do
  describe '.define' do
    it 'builds a normalized workflow definition from the Ruby DSL' do
      definition = described_class.define(:invoice_closeout) do
        step :calculate_totals, handler: :calculate_totals
        step :capture_payment, handler: 'capture_payment', depends_on: :calculate_totals
        step :emit_receipt,
             handler: :emit_receipt,
             arguments: { receipt: { mode: :email } },
             depends_on: %i[calculate_totals capture_payment]
      end

      expect(definition).to be_a(Karya::Workflow::Definition)
      expect(definition.id).to eq('invoice_closeout')
      expect(definition.steps.map(&:id)).to eq(%w[calculate_totals capture_payment emit_receipt])
      expect(definition.dependencies.map { |dependency| [dependency.step_id, dependency.depends_on_step_id] }).to eq(
        [
          %w[capture_payment calculate_totals],
          %w[emit_receipt calculate_totals],
          %w[emit_receipt capture_payment]
        ]
      )
    end

    it 'rejects an empty workflow definition' do
      expect do
        described_class.define(:invoice_closeout)
      end.to raise_error(Karya::Workflow::InvalidDefinitionError, 'workflow must define at least one step')
    end
  end

  describe '.catalog' do
    it 'builds a workflow catalog from definitions' do
      definition = described_class.define(:invoice_closeout) do
        step :calculate_totals, handler: :calculate_totals
      end

      catalog = described_class.catalog(definitions: [definition])

      expect(catalog.fetch(:invoice_closeout)).to eq(definition)
    end
  end

  describe '.build_execution_binding' do
    it 'builds a workflow execution binding for existing internal callers' do
      definition = described_class.define(:invoice_closeout) do
        step :calculate_totals, handler: :calculate_totals
      end
      job = Karya::Job.new(
        id: 'job-1',
        queue: :billing,
        handler: :calculate_totals,
        state: :submission,
        created_at: Time.utc(2026, 4, 24, 12, 0, 0)
      )

      binding = described_class.send(
        :build_execution_binding,
        definition:,
        jobs_by_step_id: { calculate_totals: job },
        batch_id: 'batch-1'
      )

      expect(binding.jobs).to eq([job])
    end
  end
end
