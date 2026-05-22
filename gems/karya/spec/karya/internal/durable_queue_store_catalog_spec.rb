# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::DurableQueueStoreCatalog do
  it 'publishes the v2 durable schema version and table names' do
    expect(described_class.schema_version).to eq(2)
    expect(described_class.table_name(:jobs)).to eq('karya_queue_store_jobs')
    expect(described_class.sqlite_create_statements).not_to be_empty
    expect(described_class.table_names).to include(
      metadata: 'karya_queue_store_metadata',
      queue_entries: 'karya_queue_store_queue_entries',
      workflow_history: 'karya_queue_store_workflow_history'
    )
  end

  it 'builds a normalized Postgres durable schema with indexed queue, workflow, and policy tables' do
    schema_sql = described_class.postgres_schema_sql

    expect(schema_sql).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_metadata')
    expect(schema_sql).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_jobs')
    expect(schema_sql).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_queue_entries')
    expect(schema_sql).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_workflow_steps')
    expect(schema_sql).to include('step_sequence integer NOT NULL')
    expect(schema_sql).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_policy_state')
    expect(schema_sql).to include('CREATE INDEX IF NOT EXISTS karya_queue_store_queue_entries_lookup')
    expect(schema_sql).to include('priority DESC, insertion_sequence ASC')
  end

  it 'builds a normalized MySQL durable schema with utf8mb4 tables and indexed reservation lookups' do
    schema_sql = described_class.mysql_schema_sql

    expect(schema_sql).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_metadata')
    expect(schema_sql).to include('CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci')
    expect(schema_sql).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_reservations')
    expect(schema_sql).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_idempotency_keys')
    expect(schema_sql).to include('CREATE INDEX karya_queue_store_reservations_job_lookup')
  end

  it 'builds a normalized SQLite durable schema with durable queue and workflow tables' do
    schema_sql = described_class.sqlite_schema_sql

    expect(schema_sql).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_metadata')
    expect(schema_sql).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_queue_entries')
    expect(schema_sql).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_workflow_batches')
    expect(schema_sql).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_uniqueness_keys')
    expect(schema_sql).to include('CREATE INDEX IF NOT EXISTS karya_queue_store_jobs_state_lookup')
  end

  it 'rejects unknown table names' do
    expect { described_class.table_name(:bogus) }.to raise_error(KeyError)
  end
end
