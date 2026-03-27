# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'open3'
require 'rbconfig'

RSpec.describe Karya do
  it 'loads the canonical entrypoint' do
    expect(described_class::VERSION).to eq('0.1.0')
  end

  it 'allows direct requires for job model subfiles' do
    lib_path = File.expand_path('../lib', __dir__)
    script = <<~RUBY
      require 'karya/job_lifecycle'
      require 'karya/job'
      puts Karya::Job.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        state: :queued,
        created_at: Time.utc(2026, 3, 26, 12, 0, 0)
      ).state
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status).to be_success, stderr
    expect(stdout).to eq("queued\n")
  end
end
