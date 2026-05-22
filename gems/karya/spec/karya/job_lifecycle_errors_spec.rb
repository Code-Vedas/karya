# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::JobLifecycle do
  describe Karya::JobLifecycle::InvalidJobStateError do
    it 'inherits from Karya::Error' do
      expect(described_class).to be < Karya::Error
    end

    it 'can be raised with a message' do
      expect do
        raise described_class, 'invalid state'
      end.to raise_error(described_class, 'invalid state')
    end

    it 'can be rescued as Karya::Error' do
      expect do
        raise described_class, 'test'
      end.to raise_error(Karya::Error)
    end
  end

  describe Karya::JobLifecycle::InvalidJobTransitionError do
    it 'inherits from Karya::Error' do
      expect(described_class).to be < Karya::Error
    end

    it 'can be raised with a message' do
      expect do
        raise described_class, 'invalid transition'
      end.to raise_error(described_class, 'invalid transition')
    end

    it 'can be rescued as Karya::Error' do
      expect do
        raise described_class, 'test'
      end.to raise_error(Karya::Error)
    end
  end
end
