# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Worker::FrameworkJobExecution do
  let(:handler_class) do
    Class.new(Karya::FrameworkJob::Base) do
      def perform(account_id, force: false)
        [account_id, force]
      end
    end
  end

  let(:keyword_rest_handler_class) do
    Class.new(Karya::FrameworkJob::Base) do
      def perform(account_id, **options)
        [account_id, options]
      end
    end
  end

  let(:required_keyword_handler_class) do
    Class.new(Karya::FrameworkJob::Base) do
      def perform(account_id, force:)
        [account_id, force]
      end
    end
  end

  let(:rest_handler_class) do
    Class.new(Karya::FrameworkJob::Base) do
      def perform(*account_ids)
        account_ids
      end
    end
  end

  let(:optional_keyword_handler_class) do
    Class.new(Karya::FrameworkJob::Base) do
      def perform(account_id, force: false)
        [account_id, force]
      end
    end
  end

  let(:mixed_optional_keyword_handler_class) do
    Class.new(Karya::FrameworkJob::Base) do
      def perform(account_id, force: false, source: 'karya')
        [account_id, force, source]
      end
    end
  end

  it 'instantiates a fresh job object and dispatches positional and keyword arguments' do
    execution = described_class.new(handler_class)

    expect(
      execution.call(arguments: Karya::FrameworkJob::ArgumentCodec.dump(['acct-1'], { force: true }))
    ).to eq(['acct-1', true])
  end

  it 'rejects unsupported keyword arguments' do
    execution = described_class.new(handler_class)

    expect do
      execution.call(arguments: Karya::FrameworkJob::ArgumentCodec.dump(['acct-1'], { unexpected: true }))
    end.to raise_error(Karya::InvalidWorkerConfigurationError, /unexpected keyword arguments/)
  end

  it 'rejects missing and invalid positional arguments' do
    execution = described_class.new(handler_class)

    expect do
      execution.call(arguments: Karya::FrameworkJob::ArgumentCodec.dump([], {}))
    end.to raise_error(Karya::InvalidWorkerConfigurationError, /too few positional arguments/)

    expect do
      execution.call(arguments: Karya::FrameworkJob::ArgumentCodec.dump(%w[a b], {}))
    end.to raise_error(Karya::InvalidWorkerConfigurationError, /too many positional arguments/)
  end

  it 'supports keyrest dispatch and rejects block parameters' do
    execution = described_class.new(keyword_rest_handler_class)
    expect(
      execution.call(arguments: Karya::FrameworkJob::ArgumentCodec.dump(['acct-1'], { force: true }))
    ).to eq(['acct-1', { force: true }])

    block_handler_class = Class.new(Karya::FrameworkJob::Base) do
      def perform(&block)
        block
      end
    end

    expect do
      described_class.new(block_handler_class).call(arguments: Karya::FrameworkJob::ArgumentCodec.dump([], {}))
    end.to raise_error(Karya::InvalidWorkerConfigurationError, /must not declare block parameters/)
  end

  it 'rejects missing required keyword arguments' do
    execution = described_class.new(required_keyword_handler_class)

    expect do
      execution.call(arguments: Karya::FrameworkJob::ArgumentCodec.dump(['acct-1'], {}))
    end.to raise_error(Karya::InvalidWorkerConfigurationError, /missing required keyword arguments: force/)
  end

  it 'supports positional rest handlers and validates keyword payload types' do
    execution = described_class.new(rest_handler_class)
    expect(execution.call(arguments: Karya::FrameworkJob::ArgumentCodec.dump(%w[a b], {}))).to eq(%w[a b])

    expect do
      execution.call(arguments: { '__karya_framework_job_v' => 1, '__karya_framework_job_args' => [], '__karya_framework_job_kwargs' => 'oops' })
    end.to raise_error(Karya::InvalidWorkerConfigurationError, /keyword arguments must be a Hash/)
  end

  it 'supports empty optional keyword payloads and omitted optional keywords' do
    execution = described_class.new(optional_keyword_handler_class)

    expect(execution.call(arguments: Karya::FrameworkJob::ArgumentCodec.dump(['acct-1'], {}))).to eq(['acct-1', false])
  end

  it 'rejects non-hash keyword payloads and allows omitted optional keys in non-empty payloads' do
    execution = described_class.new(mixed_optional_keyword_handler_class)

    expect(
      execution.call(arguments: Karya::FrameworkJob::ArgumentCodec.dump(['acct-1'], { force: true }))
    ).to eq(['acct-1', true, 'karya'])

    dispatcher = described_class.new(optional_keyword_handler_class)
    expect do
      dispatcher.call(arguments: { '__karya_framework_job_v' => 1, '__karya_framework_job_args' => ['acct-1'], '__karya_framework_job_kwargs' => 'invalid' })
    end.to raise_error(Karya::InvalidWorkerConfigurationError, /keyword arguments must be a Hash/)
  end

  it 'rejects non-hash keyword arguments at the dispatcher level' do
    dispatcher_class = described_class.const_get(:PerformDispatcher, false)
    dispatcher = dispatcher_class.new(parameters: optional_keyword_handler_class.instance_method(:perform).parameters)

    expect do
      dispatcher.send(:normalized_keyword_arguments, 'invalid')
    end.to raise_error(Karya::InvalidWorkerConfigurationError, /keyword arguments must be a Hash/)
  end
end
