# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::FrameworkConfiguration do
  subject(:configuration) { described_class.new }

  it 'tracks backend, queue store, dispatcher, and authorizer configuration' do
    queue_store = instance_double(Karya::QueueStore::Base)
    dispatcher = ->(*_) {}
    allow(Karya).to receive(:configure_backend)
    allow(Karya).to receive(:configure_queue_store)
    allow(Karya).to receive(:configure_outbound_event_dispatcher)

    configuration.backend(Karya::Backend::InMemory)
    configuration.queue_store = queue_store
    configuration.outbound_event_dispatcher = dispatcher
    configuration.operator_authorizer = dispatcher

    expect(configuration.backend_class).to eq(Karya::Backend::InMemory)
    expect(configuration.queue_store).to eq(queue_store)
    expect(configuration.outbound_event_dispatcher).to eq(dispatcher)
    expect(configuration.operator_authorizer).to eq(dispatcher)
    expect(Karya).to have_received(:configure_backend).with(Karya::Backend::InMemory)
    expect(Karya).to have_received(:configure_queue_store).with(queue_store)
    expect(Karya).to have_received(:configure_outbound_event_dispatcher).with(dispatcher)
  end

  it 'returns the configured backend when called without arguments' do
    allow(Karya).to receive(:configure_backend)

    configuration.backend(Karya::Backend::InMemory)

    expect(configuration.backend).to eq(Karya::Backend::InMemory)
  end

  it 'normalizes paths and workflow sources' do
    source = Module.new do
      def self.karya_workflow_definitions
        []
      end
    end

    configuration.job_paths = [' app/jobs ', 'lib/jobs']
    configuration.boot_files = [' config/boot.rb ']
    configuration.register_workflows(source, [source])

    expect(configuration.job_paths).to eq(['app/jobs', 'lib/jobs'])
    expect(configuration.boot_files).to eq(['config/boot.rb'])
    expect(configuration.workflow_sources).to eq([source])
  end

  it 'rejects invalid path and workflow source inputs' do
    expect { configuration.job_paths = 'app/jobs' }.to raise_error(ArgumentError, /job_paths must be an Array/)
    expect { configuration.boot_files = [1] }.to raise_error(ArgumentError, /boot_files entries must be Strings/)
    expect { configuration.register_workflows(Object.new) }.to raise_error(ArgumentError, /workflow sources must respond/)
  end
end
