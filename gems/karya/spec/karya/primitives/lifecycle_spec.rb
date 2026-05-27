# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

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
