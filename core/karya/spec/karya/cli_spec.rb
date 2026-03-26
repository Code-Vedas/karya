# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::CLI do
  describe '.start' do
    it 'prints help by default' do
      expected_output = /
        _  __.*Background\ job\ and\ workflow\ system\ ·\ v0\.1\.0
        \n(?:karya|rspec)\ commands:\n.*help\ \[COMMAND\].*version
      /mx

      expect { described_class.start([]) }
        .to output(expected_output).to_stdout
    end

    it 'prints the version' do
      expect { described_class.start(['--version']) }
        .to output(/Background job and workflow system · v0\.1\.0\n\z/).to_stdout
        .and raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
    end

    it 'shows command-specific help' do
      expect { described_class.start(%w[help version]) }
        .to output(/Background job and workflow system · v0\.1\.0\nUsage:\n.*version/m).to_stdout
    end
  end
end
