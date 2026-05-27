# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::PostgresSchemaCatalog do
  it 'renders the legacy queue-store snapshot table sql and migration' do
    expect(described_class.create_table_sql).to include('CREATE TABLE IF NOT EXISTS karya_queue_store_states')
    expect(described_class::TABLE_NAME).to eq('karya_queue_store_states')
    expect(
      described_class.render_active_record_migration(class_name: 'CreateQueueStoreStates', migration_version: '7.2')
    ).to include('class CreateQueueStoreStates < ActiveRecord::Migration[7.2]')
  end
end
