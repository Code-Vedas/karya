# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'open3'
require 'rbconfig'

RSpec.describe 'Karya::QueueStore::Internal::ReferenceQueueStore::Internal::LeaseDuration' do
  let(:described_class) do
    Karya::QueueStore::Internal::ReferenceQueueStore.const_get(:Internal, false).const_get(:LeaseDuration, false)
  end

  it 'accepts positive rational durations' do
    expect(described_class.new(Rational(3, 2)).normalize).to eq(Rational(3, 2))
  end

  it 'rejects non-finite float durations' do
    expect do
      described_class.new(Float::INFINITY).normalize
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /lease_duration must be a positive number/)
  end

  it 'loads as a standalone file and accepts BigDecimal durations' do
    lib_path = File.expand_path('../../../../../lib', __dir__)
    script = <<~RUBY
      require 'karya/queue_store/internal/reference_queue_store/lease_duration'
      lease_duration = Karya::QueueStore::Internal::ReferenceQueueStore::Internal.const_get(:LeaseDuration, false)
      puts lease_duration.new(BigDecimal('1.5')).normalize
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status.success?).to be(true), stderr
    expect(stdout).to eq("0.15e1\n")
  end

  it 'loads as a standalone file and raises InvalidQueueStoreOperationError for invalid durations' do
    lib_path = File.expand_path('../../../../../lib', __dir__)
    script = <<~RUBY
      begin
      require 'karya/queue_store/internal/reference_queue_store/lease_duration'
      lease_duration = Karya::QueueStore::Internal::ReferenceQueueStore::Internal.const_get(:LeaseDuration, false)
      lease_duration.new(0).normalize
      rescue => e
        puts e.class.name
        puts e.message
      end
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status.success?).to be(true), stderr
    expect(stdout).to eq("Karya::InvalidQueueStoreOperationError\nlease_duration must be a positive number\n")
  end
end
