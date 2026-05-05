# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe Karya::Backend::Redis do
  subject(:backend) { described_class.new(url: 'redis://example.test:6379/0') }

  it 'loads as a standalone backend file' do
    lib_path = File.expand_path('../../../lib', __dir__)
    script = <<~RUBY
      require 'karya/backend/redis'
      puts Karya::Backend::Redis.new(url: 'redis://example.test:6379/0').identifier
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status.success?).to be(true), stderr
    expect(stdout).to eq("redis\n")
  end

  it 'exposes the backend identifier' do
    expect(backend.identifier).to eq('redis')
  end

  it 'builds the Redis queue store owned by the backend definition' do
    queue_store = backend.build_queue_store

    expect(queue_store).to be_a(Karya::QueueStore::Redis)
  end

  it 'forwards namespace and queue-store options to the queue store' do
    queue_store = described_class.new(
      url: 'redis://example.test:6379/0',
      namespace: 'payments',
      max_batch_size: 50
    ).build_queue_store

    expect(queue_store.send(:namespace)).to eq('payments')
    expect(queue_store.send(:max_batch_size)).to eq(50)
  end

  it 'declares no-op lifecycle hooks around queue-store usage' do
    queue_store = backend.build_queue_store

    expect(backend.before_start(queue_store:)).to be_nil
    expect(backend.after_stop(queue_store:)).to be_nil
  end
end
