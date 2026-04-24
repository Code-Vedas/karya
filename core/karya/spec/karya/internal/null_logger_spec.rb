# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../../lib/karya/internal/null_logger'

RSpec.describe Karya::Internal::NullLogger do
  subject(:logger) { described_class.new }

  it 'returns nil for all log levels' do
    expect(logger.debug('message', job_id: 'job-1')).to be_nil
    expect(logger.info('message', queue: 'billing')).to be_nil
    expect(logger.warn('message')).to be_nil
    expect(logger.error('message', worker_id: 'worker-1')).to be_nil
  end
end
