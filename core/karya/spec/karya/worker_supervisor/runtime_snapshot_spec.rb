# frozen_string_literal: true

RSpec.describe Karya::WorkerSupervisor::RuntimeSnapshot do
  it 'builds a frozen snapshot from a mixed-key payload' do
    snapshot = described_class.from_h(
      'worker_id' => 'worker-supervisor',
      supervisor_pid: 123,
      'queues' => ['billing'],
      configured_processes: 2,
      'configured_threads' => 4,
      phase: 'running',
      child_processes: [
        {
          'pid' => 456,
          'state' => 'running',
          'thread_count' => 1,
          'threads' => [{ 'worker_id' => 'worker-1', 'state' => 'polling' }]
        }
      ]
    )

    expect(snapshot.to_h).to eq(
      worker_id: 'worker-supervisor',
      supervisor_pid: 123,
      queues: ['billing'],
      configured_processes: 2,
      configured_threads: 4,
      phase: 'running',
      child_processes: [
        {
          pid: 456,
          state: 'running',
          thread_count: 1,
          threads: [{ worker_id: 'worker-1', state: 'polling' }]
        }
      ]
    )
    expect(snapshot).to be_frozen
  end
end
