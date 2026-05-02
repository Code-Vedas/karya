# frozen_string_literal: true

RSpec.describe Karya::Backend::Selection do
  it 'normalizes supported backend identifiers' do
    expect(described_class.normalize_identifier(:in_memory)).to eq('in_memory')
    expect(described_class.normalize_identifier('inmemory')).to eq('in_memory')
    expect(described_class.normalize_identifier('InMemory')).to eq('in_memory')
  end

  it 'rejects blank backend input' do
    expect do
      described_class.normalize_identifier('   ')
    end.to raise_error(Karya::InvalidBackendSelectionError, /backend must be present/)
  end

  it 'rejects unsupported backends' do
    expect do
      described_class.normalize_identifier('mongodb')
    end.to raise_error(Karya::UnsupportedBackendError, /unsupported backend "mongodb"/)
  end

  it 'rejects undocumented delimiter variants' do
    expect do
      described_class.normalize_identifier('in-memory')
    end.to raise_error(Karya::UnsupportedBackendError, /unsupported backend "in-memory"/)
  end

  it 'rejects backends without a defined backend implementation' do
    %w[sqlite redis postgres mysql].each do |identifier|
      expect do
        described_class.normalize_identifier(identifier)
      end.to raise_error(Karya::UnsupportedBackendError, /unsupported backend/)
    end
  end

  it 'classifies inmemory as quick setup and run' do
    selection = described_class.new('InMemory')

    expect(selection.identifier).to eq('in_memory')
    expect(selection.classification).to eq(:quick_setup_and_run)
    expect(selection.quick_setup_and_run?).to be(true)
    expect(selection.production_like_local?).to be(false)
    expect(selection.production_grade?).to be(false)
  end

  it 'exposes the class-level quick setup predicate' do
    expect(described_class.quick_setup_and_run?('InMemory')).to be(true)
  end

  it 'exposes the class-level production-like-local predicate for planned classifications' do
    expect(described_class.production_like_local?('in_memory')).to be(false)
  end

  it 'exposes the class-level production-grade predicate for planned classifications' do
    expect(described_class.production_grade?('in_memory')).to be(false)
  end

  it 'keeps planned deployment classifications internal until those backends exist' do
    expect(described_class::CLASSIFICATIONS.fetch('sqlite')).to eq(:production_like_local)
    expect(described_class::CLASSIFICATIONS.fetch('redis')).to eq(:production_grade)
    expect(described_class::CLASSIFICATIONS.fetch('postgres')).to eq(:production_grade)
    expect(described_class::CLASSIFICATIONS.fetch('mysql')).to eq(:production_grade)
  end

  it 'reports whether an identifier is supported' do
    expect(described_class.supported_identifier?('inmemory')).to be(true)
    expect(described_class.supported_identifier?('postgres')).to be(false)
    expect(described_class.supported_identifier?('mongodb')).to be(false)
  end
end
