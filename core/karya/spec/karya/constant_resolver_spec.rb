# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::ConstantResolver do
  describe '#resolve' do
    it 'resolves constant paths' do
      stub_const('ResolverSpecHandler', Class.new)

      expect(described_class.new('ResolverSpecHandler').resolve).to eq(ResolverSpecHandler)
    end

    it 'does not resolve nested constants through ancestor lookup' do
      stub_const('ResolverSpecOuter', Module.new)

      expect do
        described_class.new('ResolverSpecOuter::String').resolve
      end.to raise_error(Karya::ConstantResolutionError, /ResolverSpecOuter::String/)
    end

    it 'rejects blank constant paths' do
      expect do
        described_class.new('::').resolve
      end.to raise_error(Karya::ConstantResolutionError, /"::"/)
    end

    it 'rejects empty string constant paths' do
      expect do
        described_class.new('').resolve
      end.to raise_error(Karya::ConstantResolutionError, /must not be blank/)
    end

    it 'rejects constant paths that end with ::' do
      expect do
        described_class.new('ResolverSpecOuter::').resolve
      end.to raise_error(Karya::ConstantResolutionError, /ResolverSpecOuter::/)
    end

    it 'rejects constant paths with empty middle segments' do
      expect do
        described_class.new('ResolverSpecOuter::::String').resolve
      end.to raise_error(Karya::ConstantResolutionError, /ResolverSpecOuter::::String/)
    end

    it 'raises a Karya-specific error when resolution fails' do
      expect do
        described_class.new('MissingResolverSpecHandler').resolve
      end.to raise_error(Karya::ConstantResolutionError, /MissingResolverSpecHandler/)
    end
  end
end
