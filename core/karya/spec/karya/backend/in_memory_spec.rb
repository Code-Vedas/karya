# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe Karya::Backend::InMemory do
  subject(:backend) { described_class.new }

  it 'loads as a standalone backend file' do
    lib_path = File.expand_path('../../../lib', __dir__)
    script = <<~RUBY
      require 'karya/backend/in_memory'
      puts Karya::Backend::InMemory.new.identifier
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status.success?).to be(true), stderr
    expect(stdout).to eq("in_memory\n")
  end

  it 'exposes the normalized backend identifier' do
    expect(backend.identifier).to eq('in_memory')
  end

  it 'rejects unexpected backend options' do
    expect do
      described_class.new(url: 'redis://example.test:6379/0')
    end.to raise_error(
      Karya::InvalidBackendConfigurationError,
      'Karya::Backend::InMemory does not accept backend options: :url'
    )
  end

  it 'builds the queue store provider owned by the backend definition' do
    queue_store = backend.build_queue_store

    expect(queue_store).to be_a(Karya::QueueStore::InMemory)
  end

  it 'declares no-op lifecycle hooks around queue-store usage' do
    queue_store = backend.build_queue_store

    expect(backend.before_start(queue_store:)).to be_nil
    expect(backend.after_stop(queue_store:)).to be_nil
  end
end
