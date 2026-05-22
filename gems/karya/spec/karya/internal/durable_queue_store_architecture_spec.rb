# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStore do
  describe 'persisted durable queue-store architecture' do
    it 'keeps ReferenceQueueStore ownership on InMemory only' do
      in_memory_ancestor_names = Karya::QueueStore::InMemory.ancestors.map(&:name)
      sqlite_ancestor_names = Karya::QueueStore::SQLite.ancestors.map(&:name)
      postgres_ancestor_names = Karya::QueueStore::Postgres.ancestors.map(&:name)
      mysql_ancestor_names = Karya::QueueStore::MySQL.ancestors.map(&:name)
      redis_ancestor_names = Karya::QueueStore::Redis.ancestors.map(&:name)

      expect(in_memory_ancestor_names).to include('Karya::QueueStore::Internal::ReferenceQueueStore')
      expect(sqlite_ancestor_names).not_to include('Karya::QueueStore::Internal::ReferenceQueueStore')
      expect(postgres_ancestor_names).not_to include('Karya::QueueStore::Internal::ReferenceQueueStore')
      expect(mysql_ancestor_names).not_to include('Karya::QueueStore::Internal::ReferenceQueueStore')
      expect(redis_ancestor_names).not_to include('Karya::QueueStore::Internal::ReferenceQueueStore')
    end

    it 'does not expose snapshot restore or persist hooks on persisted state stores' do
      stores = [
        Karya::QueueStore::SQLite::Internal::DurableStateStore,
        Karya::QueueStore::Postgres::Internal::DurableStateStore,
        Karya::QueueStore::MySQL::Internal::DurableStateStore,
        Karya::QueueStore::Redis::Internal::DurableStateStore
      ]

      stores.each do |store_class|
        expect(store_class.instance_methods(false)).not_to include(:load_snapshot, :load_reserve_snapshot, :persist_snapshot)
      end
    end

    it 'does not define snapshot projection or rehydration runtime classes' do
      expect(defined?(Karya::Internal::DurableQueueStore::StoreStateProjection)).to be_nil
      expect(defined?(Karya::Internal::DurableQueueStore::StoreStateRehydrator)).to be_nil
    end

    it 'does not route persisted workflow APIs through Unsupported operations' do
      workflow_operations = [
        Karya::Internal::DurableQueueStore::Operations::EnqueueWorkflow,
        Karya::Internal::DurableQueueStore::Operations::WorkflowSnapshot,
        Karya::Internal::DurableQueueStore::Operations::WorkflowHistory,
        Karya::Internal::DurableQueueStore::Operations::QueryWorkflow,
        Karya::Internal::DurableQueueStore::Operations::DeliverWorkflowSignal,
        Karya::Internal::DurableQueueStore::Operations::DeliverWorkflowEvent,
        Karya::Internal::DurableQueueStore::Operations::PauseWorkflow,
        Karya::Internal::DurableQueueStore::Operations::ResumeWorkflow,
        Karya::Internal::DurableQueueStore::Operations::ApproveWorkflowCheckpoints,
        Karya::Internal::DurableQueueStore::Operations::RejectWorkflowCheckpoints,
        Karya::Internal::DurableQueueStore::Operations::EnqueueChildWorkflow,
        Karya::Internal::DurableQueueStore::Operations::SyncChildWorkflows,
        Karya::Internal::DurableQueueStore::Operations::RollbackWorkflow,
        Karya::Internal::DurableQueueStore::Operations::RetryWorkflowSteps,
        Karya::Internal::DurableQueueStore::Operations::DeadLetterWorkflowSteps,
        Karya::Internal::DurableQueueStore::Operations::ReplayWorkflowSteps,
        Karya::Internal::DurableQueueStore::Operations::RetryDeadLetterWorkflowSteps,
        Karya::Internal::DurableQueueStore::Operations::DiscardWorkflowSteps
      ]

      workflow_operations.each do |operation_class|
        expect(operation_class).to be < Karya::Internal::DurableQueueStore::Operation
        expect(operation_class).not_to be < Karya::Internal::DurableQueueStore::Operations::Unsupported
      end
    end
  end
end
