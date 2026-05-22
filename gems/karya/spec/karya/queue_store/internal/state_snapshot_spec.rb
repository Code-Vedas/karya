# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::QueueStore::Internal::StateSnapshot do
  let(:codec) { described_class }
  let(:json_codec) { described_class.const_get(:JsonCodec, false) }
  let(:created_at) { Time.utc(2026, 5, 22, 12, 0, 0) }

  it 'round-trips supported payload scalars, arrays, hashes, structs, jobs, and objects' do
    reservation = Karya::Reservation.new(
      token: 'token-1',
      job_id: 'job-1',
      queue: 'billing',
      worker_id: 'worker-1',
      reserved_at: created_at,
      expires_at: created_at + 60
    )
    workflow_batch = Karya::Workflow::Batch.new(
      id: 'batch-1',
      job_ids: ['job-1'],
      created_at: created_at,
      updated_at: created_at + 1
    ).freeze
    job = Karya::Job.new(
      id: 'job-1',
      queue: 'billing',
      handler: 'sync',
      state: :queued,
      created_at: created_at,
      arguments: { 'ok' => ['value'] }
    )
    payload = {
      'symbol' => :queued,
      'time' => created_at,
      'decimal' => BigDecimal('12.5'),
      'ratio' => Rational(3, 4),
      'array' => [:queued, { 'nested' => created_at }],
      'hash' => { 'queued' => 'value' },
      'reservation' => reservation,
      'workflow_batch' => workflow_batch,
      'job' => job
    }

    decoded = codec.load_payload(codec.dump_payload(payload))

    expect(decoded.fetch('symbol')).to eq(:queued)
    expect(decoded.fetch('time')).to eq(created_at)
    expect(decoded.fetch('decimal')).to eq(BigDecimal('12.5'))
    expect(decoded.fetch('ratio')).to eq(Rational(3, 4))
    expect(decoded.fetch('array')).to eq([:queued, { 'nested' => created_at }])
    expect(decoded.fetch('hash')).to eq({ 'queued' => 'value' })
    expect(decoded.fetch('reservation')).to have_attributes(token: 'token-1', worker_id: 'worker-1')
    expect(decoded.fetch('workflow_batch')).to have_attributes(
      id: workflow_batch.id,
      job_ids: workflow_batch.job_ids,
      created_at: workflow_batch.created_at,
      updated_at: workflow_batch.updated_at
    )
    expect(decoded.fetch('workflow_batch')).to be_frozen
    expect(decoded.fetch('job')).to have_attributes(id: 'job-1', arguments: { 'ok' => ['value'] })
  end

  it 'round-trips top-level arrays, hashes, and supported structs' do
    workflow_batch = Karya::Workflow::Batch.new(
      id: 'batch-2',
      job_ids: ['job-2'],
      created_at: created_at,
      updated_at: created_at + 2
    )

    expect(codec.load_payload(codec.dump_payload([:queued, 'ok']))).to eq([:queued, 'ok'])
    expect(codec.load_payload(codec.dump_payload('flag' => 'ok'))).to eq('flag' => 'ok')
    expect(codec.load_payload(codec.dump_payload(workflow_batch))).to have_attributes(
      id: 'batch-2',
      job_ids: ['job-2'],
      created_at: created_at,
      updated_at: created_at + 2
    )
  end

  it 'rejects malformed json payloads and unsupported tagged types' do
    expect do
      codec.load_payload('{not-json}')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid queue-store state snapshot: JSON::ParserError/)

    expect do
      codec.load_payload('{"__karya_type__":"bogus"}')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported queue-store state snapshot payload type/)
  end

  it 'rejects unsupported job argument symbols and non-finite floats' do
    expect do
      Karya::Internal::DurableQueueStore::PayloadCodec.dump_job_arguments('bad' => 1.5)
    end.not_to raise_error

    expect do
      codec.dump_payload(
        Karya::Job.new(
          id: 'job-symbol',
          queue: 'billing',
          handler: 'sync',
          state: :queued,
          created_at: created_at,
          arguments: { 'bad' => :symbol }
        )
      )
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /do not support Symbol job arguments/)

    expect do
      codec.dump_payload(
        Karya::Job.new(
          id: 'job-float',
          queue: 'billing',
          handler: 'sync',
          state: :queued,
          created_at: created_at,
          arguments: { 'bad' => Float::INFINITY }
        )
      )
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /do not support non-finite Float job arguments/)
  end

  it 'rejects unsupported objects, classes, symbols, and decoded payload types' do
    expect do
      codec.dump_payload(Object.new)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported queue-store state snapshot payload: Object/)

    expect do
      codec.load_payload('{"__karya_type__":"symbol","value":"bogus"}')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported queue-store state snapshot symbol/)

    expect do
      codec.load_payload('{"__karya_type__":"object","class":"String","ivars":{},"frozen":false}')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported queue-store state snapshot class: "String"/)

    expect do
      json_codec.send(:decode_value, Object.new)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported queue-store state snapshot payload: Object/)
  end

  it 'rejects missing or incomplete snapshot envelopes' do
    state = Karya::QueueStore::Internal::StoreState.new(expired_tombstone_limit: 8)
    payload = codec.dump(state:, reservation_token_sequence: 1, applied_version: 2)

    snapshot = codec.load(payload)
    expect(snapshot.fetch(:reservation_token_sequence)).to eq(1)
    expect(snapshot.fetch(:applied_version)).to eq(2)
    expect(snapshot.fetch(:state)).to be_a(Karya::QueueStore::Internal::StoreState)

    expect do
      codec.load_payload(codec.dump_payload({ reservation_token_sequence: 1, applied_version: 2 }))
      codec.send(:validate_snapshot, { reservation_token_sequence: 1, applied_version: 2 })
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'invalid queue-store state snapshot')

    expect do
      codec.send(:validate_snapshot, { state: 'not-a-state', reservation_token_sequence: 1, applied_version: 2 })
    end.to raise_error(Karya::InvalidQueueStoreOperationError, 'invalid queue-store state snapshot')
  end

  it 'maps supported Karya class names and rescues unresolved Karya constants' do
    expect(json_codec.send(:supported_karya_class_name?, 'Karya::Backpressure::Scope')).to be(true)
    expect(json_codec.send(:supported_karya_class_name?, 'Karya::Workflow::Batch')).to be(true)
    expect(json_codec.send(:supported_karya_class_name?, 'Elsewhere::Thing')).to be(false)

    expect do
      codec.load_payload('{"__karya_type__":"object","class":"Karya::MissingThing","ivars":{},"frozen":false}')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported queue-store state snapshot class: "Karya::MissingThing"/)
  end

  it 'round-trips supported internal structs and preserves frozen tagged arrays and hashes' do
    rollback_class = Karya::QueueStore::Internal::StoreState.const_get(:WorkflowRollback, false)
    rollback = rollback_class.new(
      'batch-1',
      'rollback-batch-1',
      'boom',
      created_at,
      ['job-1']
    ).freeze

    decoded_rollback = codec.load_payload(codec.dump_payload(rollback))
    decoded_array = codec.load_payload(codec.dump_payload([1, 2].freeze))
    decoded_hash = codec.load_payload(codec.dump_payload({ 'a' => 1 }.freeze))

    expect(decoded_rollback).to eq(rollback)
    expect(decoded_rollback).to be_frozen
    expect(decoded_array).to eq([1, 2])
    expect(decoded_array).to be_frozen
    expect(decoded_hash).to eq({ 'a' => 1 })
    expect(decoded_hash).to be_frozen
  end

  it 'rejects unsupported external structs and malformed tagged values' do
    unsupported_struct = Struct.new(:value).new('nope')

    expect do
      codec.dump_payload(unsupported_struct)
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported queue-store state snapshot payload:/)

    expect do
      codec.load_payload('{"__karya_type__":"array"}')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid queue-store state snapshot/)

    expect do
      codec.load_payload('{"__karya_type__":"hash"}')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid queue-store state snapshot/)

    expect do
      codec.load_payload('{"__karya_type__":"struct","class":"Karya::QueueStore::Internal::StoreState::WorkflowRollback","value":{},"frozen":false}')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /invalid queue-store state snapshot/)

    expect do
      codec.load_payload('{"__karya_type__":"object","class":"Elsewhere::Thing","ivars":{},"frozen":false}')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported queue-store state snapshot class: "Elsewhere::Thing"/)
  end

  it 'decodes plain hashes and bare arrays through the json codec' do
    expect(json_codec.send(:decode_value, ['value'])).to eq(['value'])
    expect(codec.load_payload(codec.dump_payload({ 'plain' => ['value'] }))).to eq({ 'plain' => ['value'] })
    expect(json_codec.send(:decode_plain_hash, { 'plain' => ['value'] })).to eq({ 'plain' => ['value'] })
    expect(json_codec.send(:decode_tagged_value, { 'plain' => ['value'] })).to eq({ 'plain' => ['value'] })
  end

  it 'rejects Karya constants outside the supported snapshot class list' do
    stub_const('Karya::UnsupportedSnapshotThing', Class.new)

    expect do
      json_codec.send(:resolve_karya_class, 'Karya::UnsupportedSnapshotThing')
    end.to raise_error(Karya::InvalidQueueStoreOperationError, /unsupported queue-store state snapshot class/)
  end
end
