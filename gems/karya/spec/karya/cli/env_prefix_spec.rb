# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::CLI::EnvPrefix' do
  let(:env_prefix_class) { Karya::CLI.const_get(:EnvPrefix, false) }

  it 'normalizes mixed input into an uppercase env prefix' do
    expect(env_prefix_class.new(' karya workers ').normalize).to eq('KARYA_WORKERS')
  end

  it 'rejects prefixes with no alphanumeric content' do
    expect do
      env_prefix_class.new('___').normalize
    end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /Invalid value for --env-prefix/)
  end
end
