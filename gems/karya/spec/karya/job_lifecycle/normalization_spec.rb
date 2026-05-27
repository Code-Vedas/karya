# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::JobLifecycle::Normalization do
  describe '.normalize_state_name' do
    it 'converts to lowercase string' do
      expect(described_class.normalize_state_name('QUEUED')).to eq('queued')
    end

    it 'strips whitespace' do
      expect(described_class.normalize_state_name('  queued  ')).to eq('queued')
    end

    it 'converts symbols to strings' do
      expect(described_class.normalize_state_name(:queued)).to eq('queued')
    end

    it 'replaces spaces with underscores' do
      expect(described_class.normalize_state_name('pending approval')).to eq('pending_approval')
    end

    it 'replaces hyphens with underscores' do
      expect(described_class.normalize_state_name('retry-pending')).to eq('retry_pending')
    end

    it 'replaces multiple consecutive separators with single underscore' do
      expect(described_class.normalize_state_name('pending---approval')).to eq('pending_approval')
    end

    it 'removes leading separators' do
      expect(described_class.normalize_state_name('---queued')).to eq('queued')
    end

    it 'removes trailing separators' do
      expect(described_class.normalize_state_name('queued---')).to eq('queued')
    end

    it 'handles mixed separators' do
      expect(described_class.normalize_state_name('pending-_ approval')).to eq('pending_approval')
    end

    it 'preserves digits' do
      expect(described_class.normalize_state_name('stage2_pending')).to eq('stage2_pending')
    end

    it 'removes special characters except letters, digits, and separators' do
      expect(described_class.normalize_state_name('pending@approval!')).to eq('pending_approval')
    end

    it 'handles complex normalization' do
      expect(described_class.normalize_state_name('  Pending-APPROVAL 2!  ')).to eq('pending_approval_2')
    end

    it 'raises Karya::JobLifecycle::InvalidJobStateError for blank string' do
      expect do
        described_class.normalize_state_name('')
      end.to raise_error(Karya::JobLifecycle::InvalidJobStateError, 'state must be present')
    end

    it 'raises Karya::JobLifecycle::InvalidJobStateError for whitespace-only string' do
      expect do
        described_class.normalize_state_name('   ')
      end.to raise_error(Karya::JobLifecycle::InvalidJobStateError, 'state must be present')
    end

    it 'raises Karya::JobLifecycle::InvalidJobStateError for string with only separators' do
      expect do
        described_class.normalize_state_name('---___---')
      end.to raise_error(Karya::JobLifecycle::InvalidJobStateError, 'state must be present')
    end

    it 'raises Karya::JobLifecycle::InvalidJobStateError for state name exceeding max length' do
      long_state = 'a' * 65

      expect do
        described_class.normalize_state_name(long_state)
      end.to raise_error(Karya::JobLifecycle::InvalidJobStateError, /exceeds 64 characters/)
    end

    it 'allows state name at max length' do
      max_state = 'a' * 64

      expect(described_class.normalize_state_name(max_state)).to eq(max_state)
    end
  end

  describe '.lowercase_letter?' do
    it 'returns true for lowercase letters' do
      ('a'..'z').each do |char|
        expect(described_class.lowercase_letter?(char)).to be true
      end
    end

    it 'returns false for uppercase letters' do
      expect(described_class.lowercase_letter?('A')).to be false
      expect(described_class.lowercase_letter?('Z')).to be false
    end

    it 'returns false for digits' do
      expect(described_class.lowercase_letter?('0')).to be false
      expect(described_class.lowercase_letter?('9')).to be false
    end

    it 'returns false for special characters' do
      expect(described_class.lowercase_letter?('-')).to be false
      expect(described_class.lowercase_letter?('_')).to be false
      expect(described_class.lowercase_letter?(' ')).to be false
    end
  end

  describe '.digit?' do
    it 'returns true for digits' do
      ('0'..'9').each do |char|
        expect(described_class.digit?(char)).to be true
      end
    end

    it 'returns false for letters' do
      expect(described_class.digit?('a')).to be false
      expect(described_class.digit?('Z')).to be false
    end

    it 'returns false for special characters' do
      expect(described_class.digit?('-')).to be false
      expect(described_class.digit?('_')).to be false
    end
  end

  describe '.raise_blank_state_error!' do
    it 'raises Karya::JobLifecycle::InvalidJobStateError with correct message' do
      expect do
        described_class.raise_blank_state_error!
      end.to raise_error(Karya::JobLifecycle::InvalidJobStateError, 'state must be present')
    end
  end
end
