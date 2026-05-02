# frozen_string_literal: true

RSpec.describe Karya::Backend::Selection do
  it 'normalizes supported backend identifiers' do
    expect(described_class.normalize_identifier(:in_memory)).to eq('in_memory')
    expect(described_class.normalize_identifier('inmemory')).to eq('in_memory')
    expect(described_class.normalize_identifier('InMemory')).to eq('in_memory')
    expect(described_class.normalize_identifier('PostgreSQL')).to eq('postgres')
    expect(described_class.normalize_identifier('MySQL')).to eq('mysql')
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

  it 'classifies sqlite as production-like but local' do
    selection = described_class.new('SQLite')

    expect(selection.identifier).to eq('sqlite')
    expect(selection.classification).to eq(:production_like_local)
    expect(selection.quick_setup_and_run?).to be(false)
    expect(selection.production_like_local?).to be(true)
    expect(selection.production_grade?).to be(false)
  end

  it 'exposes the class-level production-like-local predicate' do
    expect(described_class.production_like_local?('SQLite')).to be(true)
  end

  it 'classifies redis, postgres, and mysql as production-grade' do
    %w[Redis Postgres MySQL].each do |identifier|
      selection = described_class.new(identifier)

      expect(selection.classification).to eq(:production_grade)
      expect(selection.production_grade?).to be(true)
    end
  end

  it 'exposes the class-level production-grade predicate' do
    expect(described_class.production_grade?('Postgres')).to be(true)
  end

  it 'reports whether an identifier is supported' do
    expect(described_class.supported_identifier?('postgres')).to be(true)
    expect(described_class.supported_identifier?('mongodb')).to be(false)
  end
end
