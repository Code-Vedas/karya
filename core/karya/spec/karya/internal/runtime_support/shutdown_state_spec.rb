# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::RuntimeSupport::ShutdownState do
  it 'returns false when begin_drain is requested after draining has already started' do
    state = described_class.new

    expect(state.begin_drain).to be(true)
    expect(state.begin_drain).to be(false)
  end

  it 'returns false when force_stop! is requested after force-stop has already started' do
    state = described_class.new

    expect(state.force_stop!).to be(true)
    expect(state.force_stop!).to be(false)
  end
end
