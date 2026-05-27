# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::FrameworkJob::ArgumentCodec do
  describe '.dump' do
    it 'serializes positional and keyword arguments into a Karya-owned envelope' do
      envelope = described_class.dump(['account-1'], { force: true, metadata: { source: 'spec' } })

      expect(envelope).to eq(
        '__karya_framework_job_v' => 1,
        '__karya_framework_job_args' => ['account-1'],
        '__karya_framework_job_kwargs' => {
          'force' => true,
          'metadata' => { 'source' => 'spec' }
        }
      )
      expect(envelope).to be_frozen
    end

    it 'rejects invalid positional and keyword argument containers' do
      expect do
        described_class.dump({}, {})
      end.to raise_error(ArgumentError, /args must be an Array/)

      expect do
        described_class.dump([], [])
      end.to raise_error(ArgumentError, /kwargs must be a Hash/)
    end
  end

  describe '.load' do
    it 'returns mutable positional and keyword arguments' do
      positional_arguments, keyword_arguments = described_class.load(
        described_class.dump(['account-1'], { metadata: { source: 'spec' } })
      )

      positional_arguments << 'account-2'
      keyword_arguments.fetch('metadata')['source'] = 'mutated'

      expect(positional_arguments).to eq(%w[account-1 account-2])
      expect(keyword_arguments).to eq('metadata' => { 'source' => 'mutated' })
    end

    it 'rejects invalid envelopes' do
      expect do
        described_class.load({})
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /missing the version envelope/)

      expect do
        described_class.load([])
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /must be a Hash/)
    end

    it 'rejects unsupported versions and malformed argument payloads' do
      expect do
        described_class.load('__karya_framework_job_v' => 2, '__karya_framework_job_args' => [], '__karya_framework_job_kwargs' => {})
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /unsupported framework job argument version/)

      expect do
        described_class.load('__karya_framework_job_v' => 1, '__karya_framework_job_args' => {}, '__karya_framework_job_kwargs' => {})
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /positional arguments must be an Array/)

      expect do
        described_class.load('__karya_framework_job_v' => 1, '__karya_framework_job_args' => [], '__karya_framework_job_kwargs' => [])
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /keyword arguments must be a Hash/)

      expect do
        described_class.load('__karya_framework_job_v' => 1, '__karya_framework_job_kwargs' => {})
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /missing positional arguments/)

      expect do
        described_class.load('__karya_framework_job_v' => 1, '__karya_framework_job_args' => [])
      end.to raise_error(Karya::InvalidWorkerConfigurationError, /missing keyword arguments/)
    end
  end

  describe '.framework_job_arguments?' do
    it 'detects the framework job envelope' do
      expect(described_class.framework_job_arguments?(described_class.dump([], {}))).to be(true)
      expect(described_class.framework_job_arguments?(described_class.dump([], { metadata: [{ source: 'spec' }] }))).to be(true)
      expect(described_class.framework_job_arguments?({})).to be(false)
    end
  end
end
