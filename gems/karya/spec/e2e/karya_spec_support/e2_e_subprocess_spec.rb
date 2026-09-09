# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../spec_helper'
require File.expand_path('../../../../../spec/support/e2e_subprocess', __dir__)

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
end
