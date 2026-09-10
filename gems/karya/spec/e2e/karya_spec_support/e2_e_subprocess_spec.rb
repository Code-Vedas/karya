# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../spec_helper'
require File.expand_path('../../../../../spec/support/e2e_subprocess', __dir__)
require 'English'

RSpec.describe KaryaSpecSupport::E2ESubprocess, :e2e, :integration do
  it 'bounds capture when a forked descendant retains an output pipe' do
    command = [
      RbConfig.ruby,
      '-e',
      <<~RUBY
        fork do
          Signal.trap('TERM', 'IGNORE')
          loop { sleep 0.1 }
        end
      RUBY
    ]

    expect do
      Timeout.timeout(5) do
        described_class.capture(*command, timeout: 0.5)
      end
    end.to raise_error(Timeout::Error, /subprocess timed out after 0.5s/)
  end

  it 'terminates a descendant that outlives its leader without retaining output pipes' do
    command = [
      RbConfig.ruby,
      '-e',
      <<~RUBY
        fork do
          1.upto(255) do |file_descriptor|
            IO.for_fd(file_descriptor).close
          rescue Errno::EBADF
            nil
          end
          Signal.trap('TERM', 'IGNORE')
          loop { sleep 0.1 }
        end
        exit! 0
      RUBY
    ]

    _stdout, _stderr, status = described_class.capture(*command, timeout: 2)

    expect(status).to be_success
  end

  it 'preserves an active failure when cleanup also fails' do
    process = instance_double(described_class)
    cleanup_error = described_class::CleanupError.new('cleanup failed')
    allow(process).to receive(:close).and_raise(cleanup_error)

    expect do
      raise 'primary failure'
    ensure
      described_class.close_preserving_failure(process, active_exception: $ERROR_INFO)
    end.to raise_error(RuntimeError, 'primary failure').and output(/cleanup failed/).to_stderr
  end
end
