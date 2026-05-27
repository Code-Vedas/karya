# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::ActiveJobLoader do
  it 'requires ActiveJob when available' do
    allow(described_class).to receive(:require).and_return(true)

    expect(described_class.require!).to be(true)
  end

  it 'raises a guided load error when ActiveJob cannot be loaded' do
    allow(described_class).to receive(:require).and_raise(LoadError, 'missing active_job')

    expect do
      described_class.require!
    end.to raise_error(LoadError, /cannot load active_job/)
  end
end
