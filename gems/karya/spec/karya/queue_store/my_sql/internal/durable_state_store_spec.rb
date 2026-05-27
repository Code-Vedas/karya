# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::MySQL::Internal::DurableStateStore do
  let(:statement_class) do
    Class.new do
      def execute(*_binds); end
    end
  end
  let(:connection_class) do
    statement_type = statement_class
    Class.new do
      define_method(:prepare) do |_sql|
        statement_type
      end
    end
  end
  let(:connection) { instance_double(connection_class) }
  let(:store) { described_class.new(connection:) }

  it 'normalizes time and integer string columns' do
    expect(store.send(:normalize_value, :updated_at, nil)).to be_nil
    expect(store.send(:normalize_value, :updated_at, '2026-05-23T12:00:00Z')).to eq(Time.utc(2026, 5, 23, 12, 0, 0))
    expect(store.send(:normalize_value, :attempt, '5')).to eq(5)
  end

  it 'selects rows, executes writes, and normalizes mysql wall-clock times' do
    statement = instance_double(statement_class)
    time_value = Time.new(2026, 5, 23, 12, 0, 0, '+05:30')

    allow(connection).to receive(:prepare).with('SELECT 1').and_return(statement)
    allow(statement).to receive(:execute).with('job-1').and_return(
      [{ 'updated_at' => time_value, 'attempt' => '5', 'state' => 'queued' }]
    )
    allow(connection).to receive(:prepare).with('UPDATE jobs SET state = ?').and_return(statement)
    allow(statement).to receive(:execute).with('queued').and_return(:ok)

    expect(store.send(:select_all, 'SELECT 1', ['job-1'])).to eq(
      [{ updated_at: Time.utc(2026, 5, 23, 12, 0, 0), attempt: 5, state: 'queued' }]
    )
    expect(store.send(:execute_write, 'UPDATE jobs SET state = ?', ['queued'])).to eq(:ok)
    expect(store.send(:placeholder, 2)).to eq('?')
    expect(store.send(:normalize_value, :updated_at, time_value)).to eq(Time.utc(2026, 5, 23, 12, 0, 0))
    expect(store.send(:normalize_value, :state, 'queued')).to eq('queued')
  end
end
