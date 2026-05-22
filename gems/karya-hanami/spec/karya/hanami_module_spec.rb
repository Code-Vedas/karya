# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Hanami do
  let(:backend_class) do
    Class.new do
      include Karya::Backend::Base

      def identifier = 'test'
      def build_queue_store = Karya::QueueStore::InMemory.new(token_generator: -> { 'lease-token' })
    end
  end

  it 'executes support and host-runtime wrappers directly on the framework module' do
    described_class.instance_variable_set(:@support, nil)

    expect(described_class.support).to be_a(Karya::Internal::FrameworkSupport)
    expect(described_class.build_host_runtime(backend_class:, backend_options: {})).to be_a(Karya::FrameworkRuntime::HostRuntime)
  ensure
    described_class.instance_variable_set(:@support, nil)
    Karya::FrameworkRuntime.reset_shared_runtime!
  end
end
