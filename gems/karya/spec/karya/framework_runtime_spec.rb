# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::FrameworkRuntime do
  let(:backend_class) do
    Class.new do
      include Karya::Backend::Base

      def initialize(**_options)
        @queue_store = Karya::QueueStore::InMemory.new(token_generator: -> { 'lease-token' })
      end

      attr_reader :queue_store

      def identifier = 'test'
      def build_queue_store = queue_store
    end
  end

  around do |example|
    example.run
  ensure
    Karya::Hooks.reset!
    described_class.reset_shared_runtime!
  end

  it 'requires a configured backend when building from global configuration' do
    expect do
      described_class.build(backend_class: nil, backend_options: {})
    end.to raise_error(Karya::FrameworkRuntime::MissingBackendError, /backend must be configured/)
  end

  it 'starts a host runtime and exposes health, readiness, operator, and probe payloads' do
    runtime = described_class.build(backend_class:, backend_options: {})

    runtime.start
    now = Time.utc(2026, 5, 21, 12, 0, 0)

    expect(runtime.health_payload).to eq(
      'status' => 'ok',
      'backend' => 'test',
      'queue_store' => 'Karya::QueueStore::InMemory'
    )
    expect(runtime.readiness_payload).to include(
      'status' => 'ready',
      'backend' => 'test',
      'queue_store' => 'Karya::QueueStore::InMemory'
    )
    expect(runtime.operator_payload(mount_path: '/karya')).to include(
      'backend' => 'test',
      'mount_path' => '/karya'
    )
    expect(
      runtime.runtime_probe_payload(
        job_prefix: 'framework-probe',
        worker_id: 'probe-worker',
        mount_path: '/karya',
        now:
      ).fetch('job_id')
    ).to start_with('framework-probe-')
  ensure
    runtime&.stop
  end

  it 'starts and stops runtimes through the shared builder helper' do
    yielded_runtime = nil

    described_class.with_started_runtime(backend_class:, backend_options: {}) do |runtime|
      yielded_runtime = runtime
      expect(runtime.started?).to be(true)
    end

    expect(yielded_runtime.started?).to be(false)
  end

  it 'handles already-started and already-stopped lifecycle calls' do
    runtime = described_class.build(backend_class:, backend_options: {})

    runtime.start
    expect(runtime.start).to equal(runtime)
    expect(runtime.stop).to be_nil
    expect(runtime.stop).to be_nil
  end

  it 'starts lazily when host payloads are requested before explicit startup' do
    runtime = described_class.build(backend_class:, backend_options: {})

    expect(runtime.health_payload.fetch('status')).to eq('ok')
  ensure
    runtime&.stop
  end

  it 'starts lazily for readiness, operator, and probe payloads on fresh runtimes' do
    readiness_runtime = described_class.build(backend_class:, backend_options: {})
    operator_runtime = described_class.build(backend_class:, backend_options: {})
    probe_runtime = described_class.build(backend_class:, backend_options: {})

    expect(readiness_runtime.readiness_payload.fetch('status')).to eq('ready')
    expect(operator_runtime.operator_payload.fetch('backend')).to eq('test')
    expect(probe_runtime.runtime_probe_payload(job_prefix: 'lazy-probe', worker_id: 'lazy-worker').fetch('job_id')).to start_with('lazy-probe-')
  ensure
    readiness_runtime&.stop
    operator_runtime&.stop
    probe_runtime&.stop
  end

  it 'cleans up safely when runtime creation fails before startup' do
    expect do
      described_class.with_started_runtime(backend_class: nil, backend_options: {}) { |_runtime| nil }
    end.to raise_error(Karya::FrameworkRuntime::MissingBackendError)
  end

  it 'restores the queue store ivar when none was configured before startup' do
    Karya.remove_instance_variable(:@queue_store) if Karya.instance_variable_defined?(:@queue_store)
    runtime = described_class.build(backend_class:, backend_options: {})

    runtime.start
    expect(Karya.queue_store).to equal(runtime.queue_store)
    runtime.stop

    expect(Karya.instance_variable_defined?(:@queue_store)).to be(false)
  end

  it 'stops cleanly when no prior queue store existed and the ivar is already absent' do
    Karya.remove_instance_variable(:@queue_store) if Karya.instance_variable_defined?(:@queue_store)
    runtime = described_class.build(backend_class:, backend_options: {})

    runtime.start
    Karya.remove_instance_variable(:@queue_store) if Karya.instance_variable_defined?(:@queue_store)

    expect(runtime.stop).to be_nil
    expect(Karya.instance_variable_defined?(:@queue_store)).to be(false)
  end

  it 'reuses and resets the shared runtime cache' do
    first = described_class.shared_runtime(backend_class:, backend_options: {})
    second = described_class.shared_runtime(backend_class:, backend_options: {})

    expect(second).to equal(first)
    expect(described_class.current_runtime).to equal(first)

    described_class.reset_shared_runtime!

    expect(described_class.current_runtime).to be_nil
  end

  it 'does not leave the shared runtime queue store attached to the process queue-store configuration' do
    queue_store = instance_double(Karya::QueueStore::Base)
    Karya.configure_queue_store(queue_store)

    runtime = described_class.shared_runtime(backend_class:, backend_options: {})

    expect(runtime.queue_store).not_to equal(queue_store)
    expect(Karya.queue_store).to equal(queue_store)
  ensure
    described_class.reset_shared_runtime!
    Karya.configure_queue_store(nil)
  end

  it 'treats detach_queue_store! as a no-op before startup and after an earlier detach' do
    queue_store = instance_double(Karya::QueueStore::Base)
    Karya.configure_queue_store(queue_store)
    runtime = described_class.build(backend_class:, backend_options: {})

    expect(runtime.__send__(:detach_queue_store)).to equal(runtime)

    runtime.start
    expect(runtime.__send__(:detach_queue_store)).to equal(runtime)
    expect(runtime.__send__(:detach_queue_store)).to equal(runtime)
    expect(Karya.queue_store).to equal(queue_store)
  ensure
    runtime&.stop
    Karya.configure_queue_store(nil)
  end

  it 'dispatches runtime build, start, and stop hooks' do
    calls = []
    Karya::Hooks.register(:runtime_build, ->(payload) { calls << ['build', payload.fetch('backend_class')] })
    Karya::Hooks.register(:runtime_start, ->(payload) { calls << ['start', payload.fetch('backend')] })
    Karya::Hooks.register(:runtime_stop, ->(payload) { calls << ['stop', payload.fetch('backend')] })

    runtime = described_class.build(backend_class:, backend_options: {})
    runtime.start
    runtime.stop

    expect(calls).to eq([
                          ['build', backend_class.name],
                          %w[start test],
                          %w[stop test]
                        ])
  end

  it 'builds runtime hook payloads without started backend state' do
    runtime = described_class.build(backend_class:, backend_options: {})

    expect(runtime.send(:runtime_payload)).to eq(
      'backend_class' => backend_class.name,
      'backend_options' => {}
    )
  end
end
