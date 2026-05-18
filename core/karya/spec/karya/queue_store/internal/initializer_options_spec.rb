# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe Karya::QueueStore::Internal::InitializerOptions do
  it 'loads as a standalone file and provides the default token generator' do
    lib_path = File.expand_path('../../../../lib', __dir__)
    script = <<~RUBY
      require 'karya/queue_store/internal/initializer_options'
      puts Karya::QueueStore::Internal::InitializerOptions.new({}).token_generator.call.class
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status.success?).to be(true), stderr
    expect(stdout).to eq("String\n")
  end
end
