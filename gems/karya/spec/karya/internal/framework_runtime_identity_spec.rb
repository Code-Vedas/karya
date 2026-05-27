# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::FrameworkRuntimeIdentity do
  it 'normalizes queues and derives worker identity' do
    queues = described_class.parse_queues('billing,critical')

    expect(queues).to eq(%w[billing critical])
    expect(described_class.worker_name(queues: %w[critical billing])).to eq('billing-critical')
    expect(described_class.worker_name(queues: queues, name: 'worker_one')).to eq('worker_one')
    expect(described_class.worker_id(framework_name: 'rails', queues: queues)).to eq('rails-billing-critical')
  end

  it 'builds and prepares the inferred state file path' do
    Dir.mktmpdir('framework-runtime-identity-') do |root|
      state_file = described_class.state_file(root_path: root, queues: ['billing'])
      ensured = described_class.ensure_state_directory!(state_file)

      expect(ensured).to eq(state_file)
      expect(File.directory?(File.dirname(state_file))).to be(true)
    end
  end

  it 'rejects empty queue input' do
    expect { described_class.parse_queues(nil) }.to raise_error(ArgumentError, /at least one queue is required/)
  end

  it 'rejects unsafe queue and worker names for runtime state paths' do
    expect do
      described_class.parse_queues('../billing')
    end.to raise_error(ArgumentError, /queue must contain only letters, numbers, hyphens, and underscores/)

    expect do
      described_class.worker_name(queues: ['billing'], name: '../../../etc/karya')
    end.to raise_error(ArgumentError, /worker_name must contain only letters, numbers, hyphens, and underscores/)
  end
end
