# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Hanami::CLI::Work do
  it 'normalizes queues and delegates to the shared worker runner path' do
    support_class = Class.new do
      attr_reader :received

      def initialize
        @received = []
      end

      def run_worker(**options)
        received << [:run_worker, options]
        :ok
      end
    end
    framework_class = Class.new do
      attr_reader :support

      def initialize(support)
        @support = support
      end

      def load_config_file!
        :ok
      end
    end
    support = support_class.new
    framework = framework_class.new(support)
    runtime_options = class_double(Karya::FrameworkJob::RuntimeOptions, compact: { threads: 2 })
    command = described_class.new(framework:, runtime_options:)

    result = command.call(queues: 'billing', threads: 2)

    expect(result).to eq(:ok)
    expect(runtime_options).to have_received(:compact).with(threads: 2)
    expect(support.received).to eq(
      [
        [:run_worker, { queues: ['billing'], threads: 2 }]
      ]
    )
  end

  it 'passes the worker name when one is provided' do
    support_class = Class.new do
      attr_reader :received

      def initialize
        @received = []
      end

      def run_worker(**options)
        received << options
        :ok
      end
    end
    framework_class = Class.new do
      attr_reader :support

      def initialize(support)
        @support = support
      end

      def load_config_file!
        :ok
      end
    end
    support = support_class.new
    framework = framework_class.new(support)
    runtime_options = class_double(Karya::FrameworkJob::RuntimeOptions, compact: {})
    command = described_class.new(framework:, runtime_options:)

    command.call(queues: 'billing', name: 'billing-worker')

    expect(support.received).to eq([{ queues: ['billing'], name: 'billing-worker' }])
  end
end
