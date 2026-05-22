# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::JobLifecycle do
  around do |example|
    described_class.send(:clear_extensions!)
    example.run
    described_class.send(:clear_extensions!)
  end

  describe '.normalize_state' do
    it 'normalizes string and symbol states to canonical snake_case symbols' do
      expect(described_class.normalize_state('retry-pending')).to eq(:retry_pending)
      expect(described_class.normalize_state(' Queued ')).to eq(:queued)
      expect(described_class.normalize_state(:queued)).to eq(:queued)
    end

    it 'rejects unknown states' do
      expect { described_class.normalize_state(:unknown) }
        .to raise_error(Karya::JobLifecycle::InvalidJobStateError, /Unknown job state/)
    end

    it 'rejects blank states with a presence error' do
      expect { described_class.normalize_state(nil) }
        .to raise_error(Karya::JobLifecycle::InvalidJobStateError, /state must be present/)
      expect { described_class.normalize_state('   ') }
        .to raise_error(Karya::JobLifecycle::InvalidJobStateError, /state must be present/)
      expect { described_class.normalize_state('___') }
        .to raise_error(Karya::JobLifecycle::InvalidJobStateError, /state must be present/)
    end

    it 'normalizes punctuation and spacing to snake_case names' do
      expect(described_class.normalize_state(' dead letter! ')).to eq(:dead_letter)
    end
  end

  describe '.validate_state!' do
    it 'returns known states unchanged' do
      expect(described_class.validate_state!(:queued)).to eq(:queued)
      expect(described_class.validate_state!(' Queued ')).to eq(:queued)
      expect(described_class.validate_state!('retry-pending')).to eq(:retry_pending)
    end

    it 'rejects unknown states' do
      expect { described_class.validate_state!(:unknown) }
        .to raise_error(Karya::JobLifecycle::InvalidJobStateError, /Unknown job state: "unknown"/)
    end
  end
end
