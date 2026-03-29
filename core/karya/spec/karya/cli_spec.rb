# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'tmpdir'

RSpec.describe Karya::CLI do
  describe '.start' do
    around do |example|
      original_queue_store = Karya.instance_variable_get(:@queue_store)
      original_queue_store_defined = Karya.instance_variable_defined?(:@queue_store)

      example.run
    ensure
      if original_queue_store_defined
        Karya.configure_queue_store(original_queue_store)
      elsif Karya.instance_variable_defined?(:@queue_store)
        Karya.remove_instance_variable(:@queue_store)
      end
    end

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

    it 'builds and starts a worker from CLI options' do
      worker_instance = instance_spy(Karya::Worker)
      configured_queue_store = Karya::InMemoryQueueStore.new
      handler_file = nil
      handler_directory = Dir.mktmpdir('karya-cli-handler')
      handler_file = File.join(handler_directory, 'cli_worker_handler.rb')
      File.write(handler_file, "class CliWorkerHandler\nend\n")
      Karya.configure_queue_store(configured_queue_store)

      allow(Karya::Worker).to receive(:new) do |queue_store:, worker_id:, queues:, handlers:, lease_duration:|
        expect(queue_store).to be(configured_queue_store)
        expect(worker_id).to eq('worker-cli')
        expect(queues).to eq(%w[billing email])
        expect(lease_duration).to eq(45)
        expect(handlers.keys).to eq(['billing_sync'])
        expect(handlers.fetch('billing_sync').name).to eq('CliWorkerHandler')
      end.and_return(worker_instance)

      expect do
        described_class.start([
                                'worker',
                                'billing',
                                'email',
                                '--worker-id',
                                'worker-cli',
                                '--lease-duration',
                                '45',
                                '--poll-interval',
                                '0',
                                '--require',
                                handler_file,
                                '--handler',
                                'billing_sync=CliWorkerHandler',
                                '--max-iterations',
                                '1',
                                '--stop-when-idle'
                              ])
      end.to output(/Background job and workflow system · v0\.1\.0/).to_stdout

      expect(Karya::Worker).to have_received(:new)
      expect(worker_instance).to have_received(:run).with(
        poll_interval: 0,
        max_iterations: 1,
        stop_when_idle: true
      )
    ensure
      File.delete(handler_file) if handler_file && File.exist?(handler_file)
      Dir.rmdir(handler_directory) if handler_directory && Dir.exist?(handler_directory)
    end

    it 'fails fast when no shared queue store is configured' do
      expect do
        described_class.start(%w[worker billing])
      end.to raise_error(Karya::MissingQueueStoreConfigurationError, /Karya.queue_store must be configured/)
    end
  end

  describe 'private helpers' do
    it 'rejects handler entries without NAME=CONSTANT format' do
      expect do
        described_class.const_get(:HandlerParser, false).parse(['billing_sync'])
      end.to raise_error(Thor::Error, /NAME=CONSTANT/)
    end

    it 'rejects handler constants that cannot be resolved' do
      expect do
        described_class.const_get(:HandlerParser, false).parse(['billing_sync=MissingCliWorkerHandler'])
      end.to raise_error(Thor::Error, /could not resolve handler constant/)
    end
  end
end
