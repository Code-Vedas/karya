# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::InMemory do
  subject(:store) { described_class.new(token_generator:) }

  let(:token_sequence) { (1..40).map { |index| "lease-#{index}" }.each }
  let(:token_generator) { -> { token_sequence.next } }
  let(:created_at) { Time.utc(2026, 4, 24, 12, 0, 0) }

  def workflow_job(step_id, handler: step_id, arguments: {}, priority: 0)
    Karya::Job.new(
      id: "job-#{step_id}",
      queue: :billing,
      handler:,
      arguments:,
      priority:,
      state: :submission,
      created_at:
    )
  end

  def reserve(now_offset, handler_names: nil)
    store.reserve(
      queue: 'billing',
      handler_names:,
      worker_id: "worker-#{now_offset}",
      lease_duration: 60,
      now: created_at + now_offset
    )
  end

  def run_successfully(reservation, start_offset:, complete_offset:)
    store.start_execution(reservation_token: reservation.token, now: created_at + start_offset)
    store.complete_execution(reservation_token: reservation.token, now: created_at + complete_offset)
  end

  describe '#enqueue_workflow' do
    it 'enqueues a root-only workflow as normal queued work' do
      definition = Karya::Workflow.define(:single_step) { step :root, handler: :root }

      report = store.enqueue_workflow(
        definition:,
        jobs_by_step_id: { root: workflow_job(:root) },
        batch_id: :batch_one,
        now: created_at + 1
      )

      expect(report.changed_jobs.map(&:id)).to eq(['job-root'])
      expect(store.batch_snapshot(batch_id: :batch_one, now: created_at + 2).job_ids).to eq(['job-root'])
      expect(reserve(3).job_id).to eq('job-root')
    end

    it 'reserves chained workflow steps only after each prerequisite succeeds' do
      definition = Karya::Workflow.define(:chain) do
        step :first, handler: :first
        step :second, handler: :second, depends_on: :first
        step :third, handler: :third, depends_on: :second
      end
      store.enqueue_workflow(
        definition:,
        jobs_by_step_id: {
          first: workflow_job(:first),
          second: workflow_job(:second),
          third: workflow_job(:third)
        },
        batch_id: :batch_one,
        now: created_at + 1
      )

      first = reserve(2)
      expect(first.job_id).to eq('job-first')
      expect(reserve(3)).to be_nil

      run_successfully(first, start_offset: 4, complete_offset: 5)
      second = reserve(6)
      expect(second.job_id).to eq('job-second')
      expect(reserve(7)).to be_nil

      run_successfully(second, start_offset: 8, complete_offset: 9)
      expect(reserve(10).job_id).to eq('job-third')
    end

    it 'supports fan-out after a shared prerequisite succeeds' do
      definition = Karya::Workflow.define(:fan_out) do
        step :root, handler: :root
        step :email, handler: :email, depends_on: :root
        step :ledger, handler: :ledger, depends_on: :root
      end
      store.enqueue_workflow(
        definition:,
        jobs_by_step_id: {
          root: workflow_job(:root),
          email: workflow_job(:email),
          ledger: workflow_job(:ledger)
        },
        batch_id: :batch_one,
        now: created_at + 1
      )

      root = reserve(2)
      expect(reserve(3)).to be_nil
      run_successfully(root, start_offset: 4, complete_offset: 5)

      expect([reserve(6).job_id, reserve(7).job_id]).to contain_exactly('job-email', 'job-ledger')
    end

    it 'supports fan-in only after all prerequisites succeed' do
      definition = Karya::Workflow.define(:fan_in) do
        step :capture, handler: :capture
        step :pack, handler: :pack
        step :notify, handler: :notify, depends_on: %i[capture pack]
      end
      store.enqueue_workflow(
        definition:,
        jobs_by_step_id: {
          capture: workflow_job(:capture),
          pack: workflow_job(:pack),
          notify: workflow_job(:notify)
        },
        batch_id: :batch_one,
        now: created_at + 1
      )

      capture = reserve(2)
      pack = reserve(3)
      run_successfully(capture, start_offset: 4, complete_offset: 5)
      expect(reserve(6)).to be_nil

      run_successfully(pack, start_offset: 7, complete_offset: 8)
      expect(reserve(9).job_id).to eq('job-notify')
    end

    it 'keeps dependents blocked while prerequisites are not succeeded' do
      definition = Karya::Workflow.define(:blocked_states) do
        step :root, handler: :root
        step :child, handler: :child, depends_on: :root
      end

      {
        reserved: lambda do |_isolated_store, reservation|
          reservation
        end,
        running: lambda do |isolated_store, reservation|
          isolated_store.start_execution(reservation_token: reservation.token, now: created_at + 3)
        end,
        failed: lambda do |isolated_store, reservation|
          isolated_store.start_execution(reservation_token: reservation.token, now: created_at + 3)
          isolated_store.fail_execution(reservation_token: reservation.token, now: created_at + 4, failure_classification: :error)
        end,
        retry_pending: lambda do |isolated_store, reservation|
          retry_policy = Karya::RetryPolicy.new(max_attempts: 3, base_delay: 60, multiplier: 1)
          isolated_store.start_execution(reservation_token: reservation.token, now: created_at + 3)
          isolated_store.fail_execution(
            reservation_token: reservation.token,
            now: created_at + 4,
            retry_policy:,
            failure_classification: :error
          )
        end,
        dead_letter: lambda do |isolated_store, _reservation|
          isolated_store.dead_letter_jobs(job_ids: ['job-root'], now: created_at + 3, reason: 'operator isolated')
        end,
        cancelled: lambda do |isolated_store, _reservation|
          isolated_store.cancel_jobs(job_ids: ['job-root'], now: created_at + 3)
        end
      }.each do |state_name, transition|
        isolated_store = described_class.new(token_generator: -> { "#{state_name}-lease" })
        isolated_store.enqueue_workflow(
          definition:,
          jobs_by_step_id: { root: workflow_job(:root), child: workflow_job(:child) },
          batch_id: :"batch_#{state_name}",
          now: created_at + 1
        )
        root = isolated_store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: created_at + 2)
        transition.call(isolated_store, root)

        expect(isolated_store.reserve(queue: 'billing', worker_id: 'worker-2', lease_duration: 60, now: created_at + 5)).to be_nil
      end
    end

    it 'unblocks dependents when a failed prerequisite is retried and succeeds' do
      definition = Karya::Workflow.define(:retry_unblock) do
        step :root, handler: :root
        step :child, handler: :child, depends_on: :root
      end
      store.enqueue_workflow(
        definition:,
        jobs_by_step_id: { root: workflow_job(:root), child: workflow_job(:child) },
        batch_id: :batch_one,
        now: created_at + 1
      )
      root = reserve(2)
      store.start_execution(reservation_token: root.token, now: created_at + 3)
      store.fail_execution(reservation_token: root.token, now: created_at + 4, failure_classification: :error)
      expect(reserve(5)).to be_nil

      store.retry_jobs(job_ids: ['job-root'], now: created_at + 6)
      retried_root = reserve(7)
      run_successfully(retried_root, start_offset: 8, complete_offset: 9)

      expect(reserve(10).job_id).to eq('job-child')
    end

    it 'skips blocked high-priority dependents and reserves lower-priority ready work' do
      definition = Karya::Workflow.define(:priority_gate) do
        step :root, handler: :root
        step :child, handler: :child, depends_on: :root
        step :independent, handler: :independent
      end
      store.enqueue_workflow(
        definition:,
        jobs_by_step_id: {
          root: workflow_job(:root, priority: 0),
          child: workflow_job(:child, priority: 100),
          independent: workflow_job(:independent, priority: 1)
        },
        batch_id: :batch_one,
        now: created_at + 1
      )

      expect(reserve(2).job_id).to eq('job-independent')
      expect(reserve(3).job_id).to eq('job-root')
    end

    it 'applies handler filtering after workflow readiness' do
      definition = Karya::Workflow.define(:handler_gate) do
        step :root, handler: :root
        step :child, handler: :child, depends_on: :root
      end
      store.enqueue_workflow(
        definition:,
        jobs_by_step_id: { root: workflow_job(:root), child: workflow_job(:child) },
        batch_id: :batch_one,
        now: created_at + 1
      )

      expect(reserve(2, handler_names: ['child'])).to be_nil
      root = reserve(3, handler_names: ['root'])
      run_successfully(root, start_offset: 4, complete_offset: 5)
      expect(reserve(6, handler_names: ['child']).job_id).to eq('job-child')
    end

    it 'registers workflow metadata and snapshots chain progress' do
      definition = Karya::Workflow.define(:snapshot_chain) do
        step :root, handler: :root
        step :child, handler: :child, depends_on: :root
      end
      store.enqueue_workflow(
        definition:,
        jobs_by_step_id: { root: workflow_job(:root), child: workflow_job(:child) },
        batch_id: :batch_one,
        now: created_at + 1
      )

      blocked = store.workflow_snapshot(batch_id: :batch_one, now: created_at + 2)
      expect(blocked).to have_attributes(
        workflow_id: 'snapshot_chain',
        batch_id: 'batch_one',
        job_ids: %w[job-root job-child],
        step_states: { 'root' => :queued, 'child' => :queued },
        state: :blocked
      )

      root = reserve(3)
      expect(store.workflow_snapshot(batch_id: :batch_one, now: created_at + 4).state).to eq(:running)
      run_successfully(root, start_offset: 5, complete_offset: 6)

      ready = store.workflow_snapshot(batch_id: :batch_one, now: created_at + 7)
      expect(ready.step_states).to eq('root' => :succeeded, 'child' => :queued)
      expect(ready.state).to eq(:running)
    end

    it 'snapshots fan-out and fan-in states' do
      definition = Karya::Workflow.define(:snapshot_fan_in) do
        step :capture, handler: :capture
        step :pack, handler: :pack
        step :notify, handler: :notify, depends_on: %i[capture pack]
      end
      store.enqueue_workflow(
        definition:,
        jobs_by_step_id: {
          capture: workflow_job(:capture),
          pack: workflow_job(:pack),
          notify: workflow_job(:notify)
        },
        batch_id: :batch_one,
        now: created_at + 1
      )
      capture = reserve(2)
      pack = reserve(3)

      expect(store.workflow_snapshot(batch_id: :batch_one, now: created_at + 4).state).to eq(:running)
      run_successfully(capture, start_offset: 5, complete_offset: 6)
      expect(store.workflow_snapshot(batch_id: :batch_one, now: created_at + 7).state).to eq(:running)
      run_successfully(pack, start_offset: 8, complete_offset: 9)

      expect(store.workflow_snapshot(batch_id: :batch_one, now: created_at + 10).state).to eq(:running)
    end

    it 'moves failed workflows out of failed when prerequisite jobs are retried' do
      definition = Karya::Workflow.define(:snapshot_retry) do
        step :root, handler: :root
        step :child, handler: :child, depends_on: :root
      end
      store.enqueue_workflow(
        definition:,
        jobs_by_step_id: { root: workflow_job(:root), child: workflow_job(:child) },
        batch_id: :batch_one,
        now: created_at + 1
      )
      root = reserve(2)
      store.start_execution(reservation_token: root.token, now: created_at + 3)
      store.fail_execution(reservation_token: root.token, now: created_at + 4, failure_classification: :error)
      expect(store.workflow_snapshot(batch_id: :batch_one, now: created_at + 5).state).to eq(:failed)

      store.retry_jobs(job_ids: ['job-root'], now: created_at + 6)
      expect(store.workflow_snapshot(batch_id: :batch_one, now: created_at + 7).state).to eq(:blocked)
      retried_root = reserve(8)
      run_successfully(retried_root, start_offset: 9, complete_offset: 10)

      expect(store.workflow_snapshot(batch_id: :batch_one, now: created_at + 11).state).to eq(:running)
    end

    it 'reports workflow snapshot errors for unknown and non-workflow batches' do
      expect do
        store.workflow_snapshot(batch_id: :missing, now: created_at + 1)
      end.to raise_error(Karya::Workflow::UnknownBatchError, 'batch "missing" is not registered')

      store.enqueue_many(jobs: [workflow_job(:root)], batch_id: :plain_batch, now: created_at + 2)

      expect do
        store.workflow_snapshot(batch_id: :plain_batch, now: created_at + 3)
      end.to raise_error(Karya::Workflow::InvalidExecutionError, 'batch "plain_batch" is not a workflow batch')
    end

    it 'rejects invalid workflow bindings without partial writes' do
      definition = Karya::Workflow.define(:invalid_binding) do
        step :root, handler: :root
      end

      expect do
        store.enqueue_workflow(
          definition:,
          jobs_by_step_id: { root: workflow_job(:root, handler: :wrong) },
          batch_id: :batch_one,
          now: created_at + 1
        )
      end.to raise_error(Karya::Workflow::InvalidExecutionError, 'workflow step "root" job handler must match workflow step handler')

      expect { store.batch_snapshot(batch_id: :batch_one, now: created_at + 2) }
        .to raise_error(Karya::Workflow::UnknownBatchError, 'batch "batch_one" is not registered')
      expect { store.workflow_snapshot(batch_id: :batch_one, now: created_at + 2) }
        .to raise_error(Karya::Workflow::UnknownBatchError, 'batch "batch_one" is not registered')
      expect(reserve(3)).to be_nil
    end
  end
end
