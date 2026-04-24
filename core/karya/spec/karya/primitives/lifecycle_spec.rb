# frozen_string_literal: true

RSpec.describe Karya::Primitives::Lifecycle do
  let(:error_class) { Class.new(StandardError) }
  let(:valid_lifecycle) do
    Module.new do
      def self.normalize_state(*) = nil
      def self.validate_state!(*) = nil
      def self.valid_transition?(**) = true
      def self.validate_transition!(**) = nil
      def self.terminal?(*) = false
    end
  end

  it 'accepts lifecycle objects responding to the required interface' do
    expect(described_class.new(:lifecycle, valid_lifecycle, error_class: error_class).normalize).to eq(valid_lifecycle)
  end

  it 'rejects lifecycle objects missing required methods' do
    expect do
      described_class.new(:lifecycle, Object.new, error_class: error_class).normalize
    end.to raise_error(error_class, /must respond to/)
  end
end
