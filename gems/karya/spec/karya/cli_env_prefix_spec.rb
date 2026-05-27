# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::CLI do
  let(:env_prefix_class) { described_class.const_get(:EnvPrefix, false) }

  describe 'EnvPrefix' do
    it 'normalizes env prefixes to uppercase snake case' do
      expect(env_prefix_class.new('billing-worker').normalize).to eq('BILLING_WORKER')
    end

    it 'collapses repeated non-alphanumeric separators without leading or trailing underscores' do
      expect(env_prefix_class.new('  billing---worker / sync  ').normalize).to eq('BILLING_WORKER_SYNC')
    end

    it 'rejects env prefixes without alphanumeric characters' do
      expect do
        env_prefix_class.new('---').normalize
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /Invalid value for --env-prefix/)
    end
  end
end
