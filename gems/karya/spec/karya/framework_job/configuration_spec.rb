# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::FrameworkJob::Configuration do
  it 'provides default job paths and boot files' do
    configuration = described_class.new

    expect(configuration.job_paths).to eq(['app/jobs'])
    expect(configuration.boot_files).to eq([])
  end

  it 'normalizes configured job paths and boot files' do
    configuration = described_class.new
    configuration.job_paths = [' app/jobs ', 'lib/jobs']
    configuration.boot_files = [' config/boot/jobs.rb ']

    expect(configuration.job_paths).to eq(['app/jobs', 'lib/jobs'])
    expect(configuration.boot_files).to eq(['config/boot/jobs.rb'])
  end

  it 'rejects non-array and non-string path configuration' do
    configuration = described_class.new

    expect do
      configuration.job_paths = 'app/jobs'
    end.to raise_error(ArgumentError, /job_paths must be an Array/)

    expect do
      configuration.boot_files = [Object.new]
    end.to raise_error(ArgumentError, /boot_files entries must be Strings/)
  end
end
