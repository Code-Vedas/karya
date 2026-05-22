# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::MountPath do
  it 'returns the default mount path when the scope is blank' do
    expect(described_class.build('/karya', scope: nil)).to eq('/karya')
    expect(described_class.build('/karya', scope: '///')).to eq('/karya')
  end

  it 'prefixes the default mount path with the normalized scope' do
    expect(described_class.build('/karya', scope: 'ops')).to eq('/ops/karya')
    expect(described_class.build('/karya', scope: '//ops//')).to eq('/ops/karya')
  end

  it 'normalizes scope values directly' do
    expect(described_class.normalize_scope(' /internal/ ')).to eq('internal')
    expect(described_class.normalize_scope('   ')).to be_nil
  end
end
