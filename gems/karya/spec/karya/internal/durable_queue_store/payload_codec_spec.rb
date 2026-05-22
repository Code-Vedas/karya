# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore::PayloadCodec do
  describe '.dump_job_arguments' do
    it 'rejects symbol job arguments anywhere in the value graph' do
      expect do
        described_class.dump_job_arguments([{ 'bad' => :symbol }])
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /do not support Symbol job arguments/)
    end

    it 'rejects non-finite float job arguments anywhere in the value graph' do
      expect do
        described_class.dump_job_arguments('bad' => [Float::INFINITY])
      end.to raise_error(Karya::InvalidQueueStoreOperationError, /do not support non-finite Float job arguments/)
    end

    it 'accepts finite floats nested in arrays and hashes' do
      payload = described_class.dump_job_arguments([{ 'ok' => 1.25 }])

      expect(described_class.decode(payload)).to eq([{ 'ok' => 1.25 }])
    end
  end
end
