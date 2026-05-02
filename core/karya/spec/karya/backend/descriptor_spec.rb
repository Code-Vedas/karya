# frozen_string_literal: true

RSpec.describe Karya::Backend::Descriptor do
  let(:capabilities) do
    Karya::Backend::Capabilities.new(
      job_persistence: true,
      workflow_state: true,
      schedule_state: true,
      audit_history: true,
      shared_processes: true,
      multi_node: true
    )
  end

  it 'normalizes the backend identifier and stores the classification' do
    descriptor = described_class.new(
      identifier: ' InMemory ',
      classification: :quick_setup_and_run,
      capabilities:
    )

    expect(descriptor.identifier).to eq('in_memory')
    expect(descriptor.quick_setup_and_run?).to be(true)
    expect(descriptor.production_like_local?).to be(false)
    expect(descriptor.production_grade?).to be(false)
  end

  it 'rejects unsupported classifications' do
    expect do
      described_class.new(identifier: :redis, classification: :local, capabilities:)
    end.to raise_error(Karya::InvalidBackendSelectionError, /classification must be one of/)
  end

  it 'rejects non-symbolizable classifications' do
    expect do
      described_class.new(identifier: :redis, classification: Object.new, capabilities:)
    end.to raise_error(Karya::InvalidBackendSelectionError, /classification must be one of/)
  end

  it 'requires a backend capabilities object' do
    expect do
      described_class.new(identifier: :redis, classification: :production_grade, capabilities: Object.new)
    end.to raise_error(Karya::InvalidBackendSelectionError, /capabilities must be a Karya::Backend::Capabilities/)
  end
end
