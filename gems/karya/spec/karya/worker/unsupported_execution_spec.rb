# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::Worker::UnsupportedExecution' do
  let(:unsupported_execution_class) { Karya::Worker.const_get(:UnsupportedExecution, false) }

  it 'raises a worker configuration error when called' do
    execution = unsupported_execution_class.new('billing_sync')

    expect do
      execution.call(arguments: {})
    end.to raise_error(Karya::InvalidWorkerConfigurationError, 'handler "billing_sync" must respond to #call or #perform')
  end
end
