# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::WorkerSupervisor::ChildProcessRunner' do
  let(:runner_class) { Karya::WorkerSupervisor.const_get(:ChildProcessRunner, false) }
  let(:configuration_class) { Karya::WorkerSupervisor.const_get(:Configuration, false) }
  let(:queue_store) { instance_double(Karya::QueueStore) }
  let(:child_worker_class) { class_double(Karya::Worker) }
  let(:runtime_state_store) do
    instance_double(
      Karya::WorkerSupervisor.const_get(:RuntimeStateStore, false),
      register_thread: nil,
      mark_thread_state: nil
    )
  end

  def configuration
    configuration_class.new(
      worker_id: 'worker-supervisor',
      queues: ['billing'],
      handlers: { 'billing_sync' => -> {} },
      lease_duration: 30,
      max_iterations: 1,
      threads: 1
    )
  end

  def configuration_with(**overrides)
    configuration_class.new(
      {
        worker_id: 'worker-supervisor',
        queues: ['billing'],
        handlers: { 'billing_sync' => -> {} },
        lease_duration: 30,
        max_iterations: 1,
        threads: 1
      }.merge(overrides)
    )
  end

  it 'raises child thread failures after joining the thread pool' do
    worker_instance = instance_double(Karya::Worker)
    allow(child_worker_class).to receive(:new).and_return(worker_instance)
    allow(worker_instance).to receive(:run).and_raise('boom')

    expect do
      runner_class.new(
        child_worker_class: child_worker_class,
        configuration: configuration,
        queue_store: queue_store,
        signal_subscriber: nil,
        runtime_state_store:
      ).run
    end.to raise_error(RuntimeError, /boom/)
  end

  it 'rejects non-callable signal subscriber restorers' do
    expect do
      runner_class.new(
        child_worker_class: child_worker_class,
        configuration: configuration,
        queue_store: queue_store,
        signal_subscriber: ->(_signal, _handler) { true },
        runtime_state_store:
      ).run
    end.to raise_error(
      Karya::InvalidWorkerSupervisorConfigurationError,
      /signal_subscriber must return a callable restorer responding to #call/
    )
  end

  it 'accepts nil signal subscriber restorers as no-op subscriptions' do
    worker_instance = instance_double(Karya::Worker, run: nil)
    allow(child_worker_class).to receive(:new).and_return(worker_instance)

    expect do
      runner_class.new(
        child_worker_class: child_worker_class,
        configuration: configuration,
        queue_store: queue_store,
        signal_subscriber: ->(_signal, _handler) {},
        runtime_state_store:
      ).run
    end.not_to raise_error
  end

  it 'passes nil max_iterations to child workers when the configuration is unlimited' do
    worker_instance = instance_double(Karya::Worker, run: nil)
    allow(child_worker_class).to receive(:new).and_return(worker_instance)

    runner_class.new(
      child_worker_class: child_worker_class,
      configuration: configuration_with(max_iterations: :unlimited),
      queue_store: queue_store,
      signal_subscriber: nil,
      runtime_state_store:
    ).run

    expect(worker_instance).to have_received(:run).with(
      poll_interval: 1,
      max_iterations: nil,
      stop_when_idle: false,
      shutdown_controller: respond_to(:force_stop?)
    )
  end

  it 'rejects false signal subscriber restorers' do
    expect do
      runner_class.new(
        child_worker_class: child_worker_class,
        configuration: configuration,
        queue_store: queue_store,
        signal_subscriber: ->(_signal, _handler) { false },
        runtime_state_store:
      ).run
    end.to raise_error(
      Karya::InvalidWorkerSupervisorConfigurationError,
      /signal_subscriber must return a callable restorer responding to #call/
    )
  end

  it 'logs and swallows stopped-thread state persistence failures during teardown' do
    worker_instance = instance_double(Karya::Worker, run: nil)
    logger = instance_double(Karya::Internal::NullLogger, error: nil)
    allow(child_worker_class).to receive(:new).and_return(worker_instance)
    allow(runtime_state_store).to receive(:mark_thread_state).and_raise('boom')
    allow(Karya).to receive(:logger).and_return(logger)

    expect do
      runner_class.new(
        child_worker_class: child_worker_class,
        configuration: configuration,
        queue_store: queue_store,
        signal_subscriber: nil,
        runtime_state_store:
      ).run
    end.not_to raise_error
    expect(logger).to have_received(:error).with(
      'runtime state reporting failed during child thread shutdown',
      process_pid: kind_of(Integer),
      worker_id: match(/worker-supervisor:\d+:thread-1/),
      error_class: 'RuntimeError',
      error_message: 'boom'
    )
  end
end
