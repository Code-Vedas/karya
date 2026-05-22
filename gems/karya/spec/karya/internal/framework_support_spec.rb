# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::FrameworkSupport do
  let(:job_base) do
    Class.new(Karya::FrameworkJob::Base) do
      abstract!
    end
  end
  let(:support) do
    described_class.new(framework_name: 'test', job_base:, root_path_resolver: -> { '/tmp/app' })
  end

  it 'configures and resolves authorizers' do
    config = support.configure
    authorizer = ->(request_context) { request_context == :allowed }

    support.configure_operator_authorizer(authorizer)

    expect(config).to be_a(Karya::Internal::FrameworkConfiguration)
    expect(support.framework_root_path).to eq('/tmp/app')
    expect(described_class.new(framework_name: 'test', job_base:, root_path_resolver: -> { '/tmp/app' }).operator_access_authorized?(:anyone)).to be(false)
    expect(support.operator_access_authorized?(:allowed)).to be(true)
    expect(support.operator_access_authorized?(:blocked)).to be(false)
    expect { support.configure_operator_authorizer(Object.new) }.to raise_error(ArgumentError, /must respond to #call/)
  end

  it 'supports configure without a block and clears explicit authorizers' do
    support.configure_operator_authorizer(->(*) { true })
    support.configure_operator_authorizer

    expect(support.configure).to be(support.configuration)
    expect(support.operator_authorizer).to be_nil
  end

  it 'yields configuration when configure is called with a block' do
    yielded_configuration = nil

    returned_configuration = support.configure do |configuration|
      yielded_configuration = configuration
    end

    expect(yielded_configuration).to be(returned_configuration)
  end

  it 'loads configuration through the non-bang helper' do
    allow(Karya::Internal::Config::FileLoader).to receive(:new).and_return(
      instance_double(Karya::Internal::Config::FileLoader, load: support.configuration)
    )

    expect(support.load_config_file(path: 'config/custom.yml')).to be_a(Karya::Internal::FrameworkConfiguration)
  end

  it 'discovers handlers and runs workers through the shared framework runner' do
    discovery = instance_double(Karya::FrameworkJob::Discovery, handlers: { 'BillingJob' => job_base })
    allow(Karya::FrameworkJob::Discovery).to receive(:new).and_return(discovery)
    allow(Karya::FrameworkJob::WorkerRunner).to receive(:run).and_return(:ok)

    expect(support.worker_handlers).to eq('BillingJob' => job_base)
    expect(support.run_worker(queues: ['billing'], threads: 2)).to eq(:ok)
    expect(support.runtime_state_file(queues: ['billing'])).to end_with('/tmp/karya/workers/billing.json')
  end

  it 'delegates runtime control operations' do
    allow(Karya::Internal::FrameworkRuntimeControl).to receive_messages(
      inspect: { 'state' => 'running' },
      drain: { 'ok' => true },
      force_stop: { 'ok' => true }
    )

    expect(support.runtime_inspect(queues: ['billing'])).to eq('state' => 'running')
    expect(support.runtime_drain(queues: ['billing'])).to eq('ok' => true)
    expect(support.runtime_force_stop(queues: ['billing'])).to eq('ok' => true)
  end
end
