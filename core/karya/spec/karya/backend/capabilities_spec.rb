# frozen_string_literal: true

RSpec.describe Karya::Backend::Capabilities do
  it 'stores backend capability flags and parity exceptions immutably' do
    capabilities = described_class.new(
      job_persistence: true,
      workflow_state: true,
      schedule_state: false,
      audit_history: true,
      shared_processes: true,
      multi_node: false,
      parity_exceptions: ['Local deployments stay single-node']
    )

    expect(capabilities.job_persistence?).to be(true)
    expect(capabilities.workflow_state?).to be(true)
    expect(capabilities.schedule_state?).to be(false)
    expect(capabilities.audit_history?).to be(true)
    expect(capabilities.shared_processes?).to be(true)
    expect(capabilities.multi_node?).to be(false)
    expect(capabilities.parity_exceptions).to eq(['Local deployments stay single-node'])
    expect(capabilities).to be_frozen
    expect(capabilities.parity_exceptions).to be_frozen
  end

  it 'rejects non-boolean capability flags' do
    expect do
      described_class.new(
        job_persistence: 'yes',
        workflow_state: true,
        schedule_state: true,
        audit_history: true,
        shared_processes: true,
        multi_node: true
      )
    end.to raise_error(Karya::InvalidBackendSelectionError, /job_persistence must be boolean/)
  end

  it 'rejects missing required capability flags' do
    expect do
      described_class.new(
        workflow_state: true,
        schedule_state: true,
        audit_history: true,
        shared_processes: true,
        multi_node: true
      )
    end.to raise_error(Karya::InvalidBackendSelectionError, /job_persistence must be provided/)
  end

  it 'rejects blank parity exceptions' do
    expect do
      described_class.new(
        job_persistence: true,
        workflow_state: true,
        schedule_state: true,
        audit_history: true,
        shared_processes: true,
        multi_node: true,
        parity_exceptions: ['  ']
      )
    end.to raise_error(Karya::InvalidBackendSelectionError, /parity_exceptions entries must be present/)
  end

  it 'rejects non-string parity exceptions' do
    expect do
      described_class.new(
        job_persistence: true,
        workflow_state: true,
        schedule_state: true,
        audit_history: true,
        shared_processes: true,
        multi_node: true,
        parity_exceptions: [:local_only]
      )
    end.to raise_error(Karya::InvalidBackendSelectionError, /parity_exceptions entries must be String values/)
  end

  it 'rejects non-array parity exceptions' do
    expect do
      described_class.new(
        job_persistence: true,
        workflow_state: true,
        schedule_state: true,
        audit_history: true,
        shared_processes: true,
        multi_node: true,
        parity_exceptions: 'local only'
      )
    end.to raise_error(Karya::InvalidBackendSelectionError, /parity_exceptions must be an Array/)
  end

  it 'rejects unknown capability attributes' do
    expect do
      described_class.new(
        job_persistence: true,
        workflow_state: true,
        schedule_state: true,
        audit_history: true,
        shared_processes: true,
        multi_node: true,
        durable: true
      )
    end.to raise_error(Karya::InvalidBackendSelectionError, /unknown capability attributes: durable/)
  end
end
