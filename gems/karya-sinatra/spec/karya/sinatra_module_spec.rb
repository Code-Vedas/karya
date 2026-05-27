# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Sinatra do
  let(:backend_class) do
    Class.new do
      include Karya::Backend::Base

      def identifier = 'test'
      def build_queue_store = Karya::QueueStore::InMemory.new(token_generator: -> { 'lease-token' })
    end
  end

  it 'executes support and runtime wrapper methods directly on the framework module' do
    runtime = instance_double(Karya::FrameworkRuntime::HostRuntime, health_payload: { 'status' => 'ok' })
    allow(Karya::Dashboard).to receive(:render_document).and_return('<html>Karya Dashboard</html>')
    allow(Karya::FrameworkRuntime).to receive(:build).and_call_original
    allow(Karya::FrameworkRuntime).to receive(:with_started_runtime).and_yield(runtime)
    described_class.instance_variable_set(:@support, nil)

    expect(described_class.support).to be_a(Karya::Internal::FrameworkSupport)
    expect(described_class.build_host_runtime(backend_class:, backend_options: {})).to be_a(Karya::FrameworkRuntime::HostRuntime)
    expect(described_class.with_host_runtime(backend_class:, backend_options: {}, &:health_payload)).to eq('status' => 'ok')
    expect(described_class.render_dashboard_page).to eq('<html>Karya Dashboard</html>')
    expect(Karya::Dashboard).to have_received(:render_document).with(
      title: Karya::Dashboard::DEFAULT_TITLE,
      mount_path: '/karya',
      asset_prefix: nil,
      name: 'dashboard'
    )
  ensure
    described_class.instance_variable_set(:@support, nil)
  end
end
