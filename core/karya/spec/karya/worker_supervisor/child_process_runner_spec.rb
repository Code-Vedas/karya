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

  it 'raises child thread failures after joining the thread pool' do
    configuration = configuration_class.new(
      worker_id: 'worker-supervisor',
      queues: ['billing'],
      handlers: { 'billing_sync' => -> {} },
      lease_duration: 30,
      max_iterations: 1,
      threads: 1
    )
    worker_instance = instance_double(Karya::Worker)
    allow(child_worker_class).to receive(:new).and_return(worker_instance)
    allow(worker_instance).to receive(:run).and_raise('boom')

    expect do
      runner_class.new(
        child_worker_class: child_worker_class,
        configuration: configuration,
        queue_store: queue_store,
        signal_subscriber: nil
      ).run
    end.to raise_error(RuntimeError, /boom/)
  end
end
