# frozen_string_literal: true

RSpec.describe Karya::OutboundEvents do
  let(:occurred_at) { Time.utc(2026, 4, 29, 12, 0, 0) }

  describe Karya::OutboundEvents::SchemaCatalog do
    it 'builds versioned CloudEvents-compatible envelopes for supported runtime events' do
      event = described_class.build_event(
        event_name: 'worker.job.started',
        payload: {
          reservation_token: 'lease-1',
          job_id: 'job-1',
          handler: 'billing_sync',
          queue: 'billing',
          worker_id: 'worker-1'
        },
        occurred_at:,
        event_id: 'event-1'
      )

      expect(event.to_h).to eq(
        'specversion' => '1.0',
        'id' => 'event-1',
        'source' => 'karya://workers/worker-1',
        'type' => 'io.karya.worker.job.started',
        'time' => '2026-04-29T12:00:00Z',
        'subject' => 'job-1',
        'datacontenttype' => 'application/json',
        'dataschema' => 'karya://schemas/events/io.karya.worker.job.started/v1',
        'karyaschemaversion' => 'v1',
        'data' => {
          'reservation_token' => 'lease-1',
          'job_id' => 'job-1',
          'handler' => 'billing_sync',
          'queue' => 'billing',
          'worker_id' => 'worker-1'
        }
      )
    end

    it 'rejects unsupported or incomplete outbound event payloads' do
      expect do
        described_class.build_event(
          event_name: 'worker.job.unknown',
          payload: {},
          occurred_at:,
          event_id: 'event-1'
        )
      end.to raise_error(Karya::UnsupportedOutboundEventError, 'unsupported outbound event "worker.job.unknown"')

      expect do
        described_class.build_event(
          event_name: 'worker.job.started',
          payload: { worker_id: 'worker-1' },
          occurred_at:,
          event_id: 'event-1'
        )
      end.to raise_error(
        Karya::InvalidOutboundEventError,
        'payload is missing required keys: handler, job_id, queue, reservation_token'
      )
    end

    it 'omits subject for event families without a natural target and rejects non-hash payloads' do
      event = described_class.build_event(
        event_name: 'worker.recovery.orphaned_jobs',
        payload: {
          recovered_jobs: 2,
          worker_id: 'worker-1'
        },
        occurred_at:,
        event_id: 'event-2'
      )

      expect(event.subject).to be_nil

      expect do
        described_class.build_event(
          event_name: 'worker.recovery.orphaned_jobs',
          payload: 'bad',
          occurred_at:,
          event_id: 'event-2'
        )
      end.to raise_error(Karya::InvalidOutboundEventError, 'payload must be a Hash')
    end
  end

  describe Karya::OutboundEvents::Event do
    let(:schema) do
      Karya::OutboundEvents::Schema.new(
        event_type: 'io.karya.worker.job.started',
        schema_version: 'v1',
        data_schema: 'karya://schemas/events/io.karya.worker.job.started/v1'
      )
    end

    it 'rejects invalid schema objects, non-json data values, and unknown keys' do
      expect do
        described_class.new(
          id: 'event-1',
          source: 'karya://workers/worker-1',
          schema: 'bad',
          time: occurred_at,
          data: {}
        )
      end.to raise_error(Karya::InvalidOutboundEventError, 'schema must be Karya::OutboundEvents::Schema')

      expect do
        described_class.new(
          id: 'event-1',
          source: 'karya://workers/worker-1',
          schema:,
          time: occurred_at,
          data: { 'bad' => Object.new }
        )
      end.to raise_error(Karya::InvalidOutboundEventError, 'data values must be JSON-compatible')

      expect do
        described_class.new(
          id: 'event-1',
          source: 'karya://workers/worker-1',
          schema:,
          time: occurred_at,
          data: {},
          unexpected: true
        )
      end.to raise_error(ArgumentError, 'unknown keyword: :unexpected')
    end

    it 'accepts JSON state arguments when serializing to JSON' do
      event = described_class.new(
        id: 'event-1',
        source: 'karya://workers/worker-1',
        schema:,
        time: occurred_at,
        data: { 'job_id' => 'job-1' }
      )

      json_state = JSON::State.new(indent: '  ')

      expect(JSON.parse(event.to_json(json_state))).to eq(event.to_h)
    end
  end

  describe Karya::OutboundEvents::Delivery do
    let(:schema) do
      Karya::OutboundEvents::Schema.new(
        event_type: 'io.karya.worker.job.started',
        schema_version: 'v1',
        data_schema: 'karya://schemas/events/io.karya.worker.job.started/v1'
      )
    end
    let(:event) do
      Karya::OutboundEvents::Event.new(
        id: 'event-1',
        source: 'karya://workers/worker-1',
        schema:,
        time: occurred_at,
        data: { 'job_id' => 'job-1' }
      )
    end

    it 'supports unsigned deliveries and rejects invalid event or signature input' do
      delivery = described_class.new(event:)

      expect(delivery.signature).to be_nil
      expect(delivery.headers).to eq('Content-Type' => 'application/cloudevents+json')

      expect do
        described_class.new(event: 'bad')
      end.to raise_error(Karya::InvalidOutboundEventError, 'event must be Karya::OutboundEvents::Event')

      expect do
        described_class.new(event:, signature: 'bad')
      end.to raise_error(Karya::InvalidOutboundEventError, 'signature must be Karya::OutboundEvents::WebhookSignature')
    end

    it 'serializes the normalized event instance instead of the raw initializer argument' do
      raw_event = Class.new do
        def is_a?(klass)
          klass == Karya::OutboundEvents::Event || super
        end

        def to_json(*)
          '{"raw":true}'
        end
      end.new

      normalized_event = Karya::OutboundEvents::Event.new(
        id: 'event-1',
        source: 'karya://workers/worker-1',
        schema:,
        time: occurred_at,
        data: { 'job_id' => 'job-1' }
      )

      delivery = described_class.allocate
      delivery.send(:initialize, event: normalized_event)
      expect(delivery.body).to eq(normalized_event.to_json)

      delivery_class = Class.new(described_class) do
        def self.with_normalized_event(normalized_event)
          Class.new(self) do
            define_method(:normalize_event) do |_value|
              normalized_event
            end
          end
        end

        private :normalize_event
      end

      delivery = delivery_class.with_normalized_event(normalized_event).allocate
      delivery.send(:initialize, event: raw_event)
      expect(delivery.body).to eq(normalized_event.to_json)
    end
  end

  describe Karya::OutboundEvents::WebhookSigner do
    it 'generates deterministic webhook signatures for the same bytes and timestamp' do
      signer = described_class.new(secret: 'secret')
      signature = signer.sign(body: '{"id":"event-1"}', now: occurred_at)

      expect(signature.headers).to eq(
        'Karya-Webhook-Timestamp' => '1777464000',
        'Karya-Webhook-Signature' => 'v1=92550d04b40d7e37370ac616b3a58c4fee591f8cb5d4d894999e09c538cb1b14'
      )
    end

    it 'signs the exact body bytes without trimming surrounding whitespace' do
      signer = described_class.new(secret: 'secret')

      signature = signer.sign(body: "  {\"id\":\"event-1\"}\n", now: occurred_at)
      stripped_signature = signer.sign(body: '{"id":"event-1"}', now: occurred_at)

      expect(signature.digest).not_to eq(stripped_signature.digest)
    end

    it 'rejects non-string and empty bodies' do
      signer = described_class.new(secret: 'secret')

      expect do
        signer.sign(body: :bad, now: occurred_at)
      end.to raise_error(Karya::InvalidWebhookSignatureError, 'body must be a String')

      expect do
        signer.sign(body: '', now: occurred_at)
      end.to raise_error(Karya::InvalidWebhookSignatureError, 'body must be present')
    end
  end

  describe Karya::OutboundEvents::WebhookVerifier do
    it 'verifies valid signatures and rejects tampering, mismatched secrets, and stale timestamps' do
      body = '{"id":"event-1"}'
      headers = Karya::OutboundEvents::WebhookSigner.new(secret: 'secret').sign(body:, now: occurred_at).headers
      verifier = described_class.new(secret: 'secret')

      expect(verifier.verify(body:, headers:, now: occurred_at + 60)).to be(true)
      expect(verifier.verify(body: '{"id":"event-2"}', headers:, now: occurred_at + 60)).to be(false)
      expect(described_class.new(secret: 'other').verify(body:, headers:, now: occurred_at + 60)).to be(false)
      expect(verifier.verify(body:, headers:, now: occurred_at + 301)).to be(false)
    end

    it 'rejects malformed timestamp headers' do
      headers = {
        'Karya-Webhook-Timestamp' => 'invalid',
        'Karya-Webhook-Signature' => 'v1=deadbeef'
      }

      expect(described_class.new(secret: 'secret').verify(body: '{"id":"event-1"}', headers:, now: occurred_at)).to be(false)
    end

    it 'rejects invalid header containers, malformed signature formats, and unsupported schemes' do
      verifier = described_class.new(secret: 'secret')

      expect(verifier.verify(body: '{"id":"event-1"}', headers: [], now: occurred_at)).to be(false)

      malformed_headers = {
        'Karya-Webhook-Timestamp' => occurred_at.to_i.to_s,
        'Karya-Webhook-Signature' => 'invalid'
      }
      expect(verifier.verify(body: '{"id":"event-1"}', headers: malformed_headers, now: occurred_at)).to be(false)

      unsupported_scheme_headers = {
        'Karya-Webhook-Timestamp' => occurred_at.to_i.to_s,
        'Karya-Webhook-Signature' => 'v2=deadbeef'
      }
      expect(verifier.verify(body: '{"id":"event-1"}', headers: unsupported_scheme_headers, now: occurred_at)).to be(false)
    end
  end

  describe Karya::OutboundEvents::Dispatcher do
    it 'builds signed deliveries for supported instrumentation events' do
      deliveries = []
      dispatcher = described_class.new(
        delivery_handler: ->(delivery) { deliveries << delivery },
        signer: Karya::OutboundEvents::WebhookSigner.new(secret: 'secret'),
        clock: -> { occurred_at },
        event_id_generator: -> { 'event-1' }
      )

      delivery = dispatcher.call(
        'supervisor.child.spawned',
        pid: 123,
        worker_id: 'worker-1'
      )

      expect(deliveries).to eq([delivery])
      expect(delivery.headers.fetch('Content-Type')).to eq('application/cloudevents+json')
      expect(delivery.headers.fetch('Karya-Webhook-Signature')).to start_with('v1=')
      expect(delivery.event.type).to eq('io.karya.supervisor.child.spawned')
    end

    it 'supports unsigned dispatchers and rejects clocks that do not return Time' do
      deliveries = []
      dispatcher = described_class.new(
        delivery_handler: ->(delivery) { deliveries << delivery },
        clock: -> { occurred_at },
        event_id_generator: -> { 'event-2' }
      )

      delivery = dispatcher.call(
        'worker.recovery.orphaned_jobs',
        recovered_jobs: 1,
        worker_id: 'worker-1'
      )

      expect(delivery.signature).to be_nil
      expect(deliveries).to eq([delivery])

      expect do
        described_class.new(
          delivery_handler: ->(_delivery) {},
          clock: -> { 'bad' }
        ).call('worker.recovery.orphaned_jobs', recovered_jobs: 1, worker_id: 'worker-1')
      end.to raise_error(Karya::InvalidOutboundEventError, 'clock must return a Time')
    end

    it 'rejects invalid signer objects during initialization' do
      expect do
        described_class.new(
          delivery_handler: ->(_delivery) {},
          signer: Object.new
        )
      end.to raise_error(Karya::InvalidOutboundEventError, 'signer must be Karya::OutboundEvents::WebhookSigner')
    end

    it 'can be loaded directly through karya/outbound_events without worker runtime requires' do
      command = <<~RUBY
        require_relative '../../lib/karya/base'
        require_relative '../../lib/karya/outbound_events'
        dispatcher = Karya::OutboundEvents::Dispatcher.new(delivery_handler: ->(_delivery) {})
        abort('dispatcher missing') unless dispatcher.is_a?(Karya::OutboundEvents::Dispatcher)
      RUBY

      expect(system('ruby', '-e', command, chdir: __dir__)).to be(true)
    end
  end

  describe 'shared value normalizers' do
    it 'covers optional strings, timestamps, and JSON payload normalization branches' do
      error_class = Karya::InvalidOutboundEventError

      expect(Karya::OutboundEvents::OptionalString.new(:subject, nil, error_class:).normalize).to be_nil
      expect(Karya::OutboundEvents::OptionalString.new(:subject, 'job-1', error_class:).normalize).to eq('job-1')
      expect do
        Karya::OutboundEvents::PresentString.new(:subject, '   ', error_class:).normalize
      end.to raise_error(Karya::InvalidOutboundEventError, 'subject must be present')
      expect do
        Karya::OutboundEvents::Timestamp.new(:time, 'bad', error_class:).normalize
      end.to raise_error(Karya::InvalidOutboundEventError, 'time must be a Time')

      normalized_hash = Karya::OutboundEvents::JsonHash.new(
        { role: :ops, 'attempts' => [1, { 'nested' => 'ok' }] },
        error_class:,
        hash_message: 'payload must be a Hash',
        value_message: 'payload values must be JSON-compatible'
      ).normalize
      expect(normalized_hash).to eq(
        'role' => 'ops',
        'attempts' => [1, { 'nested' => 'ok' }]
      )

      expect do
        Karya::OutboundEvents::JsonHash.new(
          [],
          error_class:,
          hash_message: 'payload must be a Hash',
          value_message: 'payload values must be JSON-compatible'
        ).normalize
      end.to raise_error(Karya::InvalidOutboundEventError, 'payload must be a Hash')

      expect do
        Karya::OutboundEvents::JsonHash.new(
          { 'bad' => Object.new },
          error_class:,
          hash_message: 'payload must be a Hash',
          value_message: 'payload values must be JSON-compatible'
        ).normalize
      end.to raise_error(Karya::InvalidOutboundEventError, 'payload values must be JSON-compatible')
    end
  end
end
