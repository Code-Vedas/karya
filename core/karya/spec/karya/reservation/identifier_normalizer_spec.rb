# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Reservation::IdentifierNormalizer do
  describe '#normalize' do
    it 'converts to string and strips whitespace' do
      normalizer = described_class.new(:token, '  tok123  ')
      expect(normalizer.normalize).to eq('tok123')
    end

    it 'converts symbol to string' do
      normalizer = described_class.new(:job_id, :job456)
      expect(normalizer.normalize).to eq('job456')
    end

    it 'converts integer to string' do
      normalizer = described_class.new(:worker_id, 789)
      expect(normalizer.normalize).to eq('789')
    end

    it 'freezes the result' do
      normalizer = described_class.new(:token, 'tok123')
      expect(normalizer.normalize).to be_frozen
    end

    it 'raises InvalidReservationAttributeError for blank value' do
      expect do
        described_class.new(:token, '   ').normalize
      end.to raise_error(Karya::InvalidReservationAttributeError, 'token must be present')
    end

    it 'raises InvalidReservationAttributeError for empty string' do
      expect do
        described_class.new(:job_id, '').normalize
      end.to raise_error(Karya::InvalidReservationAttributeError, 'job_id must be present')
    end

    it 'handles strings that become blank after stripping' do
      expect do
        described_class.new(:queue, "\n\t  \r\n").normalize
      end.to raise_error(Karya::InvalidReservationAttributeError, 'queue must be present')
    end
  end
end
