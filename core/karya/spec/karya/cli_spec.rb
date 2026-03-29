# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'tmpdir'

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

    it 'builds and starts a worker from CLI options' do
      worker_instance = instance_spy(Karya::Worker)
      handler_file = nil
      handler_directory = Dir.mktmpdir('karya-cli-handler')
      handler_file = File.join(handler_directory, 'cli_worker_handler.rb')
      File.write(handler_file, "class CliWorkerHandler\nend\n")

      allow(Karya::Worker).to receive(:new) do |queue_store:, worker_id:, queues:, handlers:, lease_duration:|
        expect(queue_store).to be_a(Karya::InMemoryQueueStore)
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
  end

  describe 'private helpers' do
    it 'rejects handler entries without NAME=CONSTANT format' do
      expect do
        described_class::HandlerParser.parse(['billing_sync'])
      end.to raise_error(Thor::Error, /NAME=CONSTANT/)
    end

    it 'rejects handler constants that cannot be resolved' do
      expect do
        described_class::HandlerParser.parse(['billing_sync=MissingCliWorkerHandler'])
      end.to raise_error(Thor::Error, /could not resolve handler constant/)
    end
  end
end
