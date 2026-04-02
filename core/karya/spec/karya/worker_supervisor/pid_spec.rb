# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::WorkerSupervisor::Pid' do
  let(:pid_class) { Karya::WorkerSupervisor.const_get(:Pid, false) }

  it 'rejects invalid fork pids' do
    expect do
      pid_class.new('bad').normalize
    end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /forker must return a positive Integer pid/)
  end
end
