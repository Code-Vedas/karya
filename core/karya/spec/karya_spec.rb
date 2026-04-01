# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'open3'
require 'rbconfig'

RSpec.describe Karya do
  around do |example|
    original_logger_defined = described_class.instance_variable_defined?(:@logger)
    original_logger = described_class.instance_variable_get(:@logger)
    original_instrumenter_defined = described_class.instance_variable_defined?(:@instrumenter)
    original_instrumenter = described_class.instance_variable_get(:@instrumenter)

    example.run
  ensure
    if original_logger_defined
      described_class.configure_logger(original_logger)
    elsif described_class.instance_variable_defined?(:@logger)
      described_class.remove_instance_variable(:@logger)
    end

    if original_instrumenter_defined
      described_class.configure_instrumenter(original_instrumenter)
    elsif described_class.instance_variable_defined?(:@instrumenter)
      described_class.remove_instance_variable(:@instrumenter)
    end
  end

  it 'loads the canonical entrypoint' do
    expect(described_class::VERSION).to eq('0.1.0')
  end

  it 'provides a null logger by default' do
    expect(described_class.logger).to be_a(Karya::Internal::NullLogger)
    expect(described_class.logger.info('hello')).to be_nil
  end

  it 'allows configuring global logger and instrumenter defaults' do
    logger = Object.new
    instrumenter = ->(_event, _payload) {}

    described_class.configure_logger(logger)
    described_class.configure_instrumenter(instrumenter)

    expect(described_class.logger).to be(logger)
    expect(described_class.instrumenter).to be(instrumenter)
  end

  it 'allows direct requires for job model subfiles' do
    lib_path = File.expand_path('../lib', __dir__)
    script = <<~RUBY
      require 'karya/job_lifecycle'
      require 'karya/job'
      puts Karya::Job.new(
        id: 'job_123',
        queue: 'billing',
        handler: 'billing_sync',
        state: :queued,
        created_at: Time.utc(2026, 3, 26, 12, 0, 0)
      ).state
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status).to be_success, stderr
    expect(stdout).to eq("queued\n")
  end

  it 'allows requiring karya/worker directly' do
    lib_path = File.expand_path('../lib', __dir__)
    script = <<~RUBY
      require 'karya/worker'
      puts Karya::Worker::DEFAULT_POLL_INTERVAL
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status).to be_success, stderr
    expect(stdout).to eq("1\n")
  end

  it 'allows requiring karya/worker_supervisor directly' do
    lib_path = File.expand_path('../lib', __dir__)
    script = <<~RUBY
      require 'karya/worker_supervisor'
      puts Karya::WorkerSupervisor::DEFAULT_PROCESSES
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status).to be_success, stderr
    expect(stdout).to eq("1\n")
  end

  it 'allows requiring karya/cli directly' do
    lib_path = File.expand_path('../lib', __dir__)
    script = <<~RUBY
      require 'karya/cli'
      puts Karya::CLI.header.include?(Karya::VERSION)
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status).to be_success, stderr
    expect(stdout).to eq("true\n")
  end

  it 'allows requiring karya/job_lifecycle/state_manager directly' do
    lib_path = File.expand_path('../lib', __dir__)
    script = <<~RUBY
      require 'karya/job_lifecycle/state_manager'
      puts Karya::JobLifecycle::StateManager.new.states.include?(:queued)
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status).to be_success, stderr
    expect(stdout).to eq("true\n")
  end

  it 'allows requiring karya/job_lifecycle/registry directly' do
    lib_path = File.expand_path('../lib', __dir__)
    script = <<~RUBY
      require 'karya/job_lifecycle/registry'
      puts Karya::JobLifecycle::Registry.new.validate_state(:queued)
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status).to be_success, stderr
    expect(stdout).to eq("queued\n")
  end
end
