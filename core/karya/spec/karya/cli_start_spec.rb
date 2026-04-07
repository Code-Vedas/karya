# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'tmpdir'

RSpec.describe Karya::CLI do
  def worker_command_args(handler_file)
    [
      'worker',
      'billing',
      'email',
      '--worker-id',
      'worker-cli',
      '--lease-duration',
      '45',
      '--processes',
      '3',
      '--threads',
      '4',
      '--state-file',
      '/tmp/karya-runtime-worker-cli.json',
      '--env-prefix',
      'billing_worker',
      '--poll-interval',
      '0',
      '--require',
      handler_file,
      '--handler',
      'billing_sync=CliWorkerHandler',
      '--max-iterations',
      '1',
      '--stop-when-idle'
    ]
  end

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

    it 'describes worker as a supervisor-managed command in help output' do
      expect { described_class.start(%w[help worker], suppress_header: true) }
        .to output(/manages processes and per-process threads/).to_stdout
    end

    it 'builds and starts a worker supervisor from CLI options' do
      supervisor_instance = instance_double(Karya::WorkerSupervisor, run: 0)
      configured_queue_store = Karya::QueueStore::InMemory.new
      handler_file = nil
      handler_directory = Dir.mktmpdir('karya-cli-handler')
      handler_file = File.join(handler_directory, 'cli_worker_handler.rb')
      File.write(handler_file, "class CliWorkerHandler\nend\n")
      Karya.configure_queue_store(configured_queue_store)

      allow(Karya::WorkerSupervisor).to receive(:new) do |**kwargs|
        expect(kwargs.fetch(:queue_store)).to be(configured_queue_store)
        expect(kwargs.fetch(:processes)).to eq(3)
        expect(kwargs.fetch(:threads)).to eq(4)
        expect(kwargs.fetch(:state_file)).to eq('/tmp/karya-runtime-worker-cli.json')
        expect(kwargs.fetch(:worker_id)).to eq('worker-cli')
        expect(kwargs.fetch(:queues)).to eq(%w[billing email])
        expect(kwargs.fetch(:lease_duration)).to eq(45)
        expect(kwargs.fetch(:poll_interval)).to eq(0)
        expect(kwargs.fetch(:max_iterations)).to eq(1)
        expect(kwargs.fetch(:stop_when_idle)).to be(true)
        expect(kwargs.fetch(:handlers).keys).to eq(['billing_sync'])
        expect(kwargs.fetch(:handlers).fetch('billing_sync').name).to eq('CliWorkerHandler')
        expect(kwargs.fetch(:signal_subscriber)).to respond_to(:call)
      end.and_return(supervisor_instance)

      expect do
        described_class.start(worker_command_args(handler_file))
      end.to output(/Background job and workflow system · v0\.1\.0/).to_stdout

      expect(Karya::WorkerSupervisor).to have_received(:new)
      expect(supervisor_instance).to have_received(:run)
    ensure
      File.delete(handler_file) if handler_file && File.exist?(handler_file)
      Dir.rmdir(handler_directory) if handler_directory && Dir.exist?(handler_directory)
    end

    it 'exits non-zero when the worker supervisor reports a forced shutdown status' do
      configured_queue_store = Karya::QueueStore::InMemory.new
      Karya.configure_queue_store(configured_queue_store)
      allow(Karya::WorkerSupervisor).to receive(:new).and_return(instance_double(Karya::WorkerSupervisor, run: 1))

      expect do
        described_class.start(%w[worker billing], suppress_header: true)
      end.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end

    it 'fails fast when no shared queue store is configured' do
      expect do
        described_class.start(%w[worker billing], suppress_header: true)
      end.to raise_error(Karya::MissingQueueStoreConfigurationError, /Karya.queue_store must be configured/)
    end

    it 'surfaces process validation failures' do
      configured_queue_store = Karya::QueueStore::InMemory.new
      Karya.configure_queue_store(configured_queue_store)

      expect do
        described_class.start(%w[worker billing --processes 0], suppress_header: true)
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /Invalid value for --processes/)
    end

    it 'rejects non-integer process values before building the supervisor' do
      configured_queue_store = Karya::QueueStore::InMemory.new
      Karya.configure_queue_store(configured_queue_store)
      allow(Karya::WorkerSupervisor).to receive(:new)

      expect do
        described_class.start(%w[worker billing --processes 1.5], suppress_header: true)
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /Invalid value for --processes/)
      expect(Karya::WorkerSupervisor).not_to have_received(:new)
    end

    it 'rejects non-integer thread values before building the supervisor' do
      configured_queue_store = Karya::QueueStore::InMemory.new
      Karya.configure_queue_store(configured_queue_store)
      allow(Karya::WorkerSupervisor).to receive(:new)

      expect do
        described_class.start(%w[worker billing --threads 1.5], suppress_header: true)
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /Invalid value for --threads/)
      expect(Karya::WorkerSupervisor).not_to have_received(:new)
    end

    it 'normalizes whole-float max_iterations before building the supervisor' do
      configured_queue_store = Karya::QueueStore::InMemory.new
      Karya.configure_queue_store(configured_queue_store)
      supervisor_instance = instance_double(Karya::WorkerSupervisor, run: 0)

      allow(Karya::WorkerSupervisor).to receive(:new) do |**kwargs|
        expect(kwargs.fetch(:max_iterations)).to eq(1)
      end.and_return(supervisor_instance)

      described_class.start(%w[worker billing --max-iterations 1.0], suppress_header: true)

      expect(supervisor_instance).to have_received(:run)
    end

    it 'rejects malformed max_iterations before building the supervisor' do
      configured_queue_store = Karya::QueueStore::InMemory.new
      Karya.configure_queue_store(configured_queue_store)
      allow(Karya::WorkerSupervisor).to receive(:new)

      expect do
        described_class.start(%w[worker billing --max-iterations 1.5], suppress_header: true)
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /Invalid value for --max-iterations/)
      expect(Karya::WorkerSupervisor).not_to have_received(:new)
    end

    it 'can suppress the header for internal callers' do
      expect { described_class.start(%w[help version], suppress_header: true) }
        .to output(/Usage:\n.*version/m).to_stdout
    end

    it 'uses env-prefixed process and thread defaults when flags are absent' do
      configured_queue_store = Karya::QueueStore::InMemory.new
      supervisor_instance = instance_double(Karya::WorkerSupervisor, run: 0)
      Karya.configure_queue_store(configured_queue_store)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('KARYA_BILLING_WORKER_PROCESSES', nil).and_return('2')
      allow(ENV).to receive(:fetch).with('KARYA_BILLING_WORKER_THREADS', nil).and_return('3')
      allow(Karya::WorkerSupervisor).to receive(:new) do |**kwargs|
        expect(kwargs.fetch(:processes)).to eq(2)
        expect(kwargs.fetch(:threads)).to eq(3)
      end.and_return(supervisor_instance)

      described_class.start(%w[worker billing --env-prefix billing-worker], suppress_header: true)

      expect(supervisor_instance).to have_received(:run)
    end

    it 'lets explicit flags override env-prefixed values' do
      configured_queue_store = Karya::QueueStore::InMemory.new
      supervisor_instance = instance_double(Karya::WorkerSupervisor, run: 0)
      Karya.configure_queue_store(configured_queue_store)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('KARYA_BILLING_WORKER_PROCESSES', nil).and_return('2')
      allow(ENV).to receive(:fetch).with('KARYA_BILLING_WORKER_THREADS', nil).and_return('3')
      allow(Karya::WorkerSupervisor).to receive(:new) do |**kwargs|
        expect(kwargs.fetch(:processes)).to eq(5)
        expect(kwargs.fetch(:threads)).to eq(6)
      end.and_return(supervisor_instance)

      described_class.start(
        %w[worker billing --env-prefix billing-worker --processes 5 --threads 6],
        suppress_header: true
      )

      expect(supervisor_instance).to have_received(:run)
    end
  end
end
