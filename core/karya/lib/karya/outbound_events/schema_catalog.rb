# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module OutboundEvents
    # Maps Karya runtime instrumentation events to versioned outbound event contracts.
    class SchemaCatalog
      SCHEMAS = {
        'worker.job.reserved' => {
          event_type: 'io.karya.worker.job.reserved',
          schema_version: 'v1',
          required_keys: %w[job_id queue reservation_token worker_id],
          subject_key: 'job_id',
          source_prefix: 'karya://workers/'
        },
        'worker.recovery.orphaned_jobs' => {
          event_type: 'io.karya.worker.recovery.orphaned_jobs',
          schema_version: 'v1',
          required_keys: %w[recovered_jobs worker_id],
          source_prefix: 'karya://workers/'
        },
        'worker.job.released' => {
          event_type: 'io.karya.worker.job.released',
          schema_version: 'v1',
          required_keys: %w[reservation_token worker_id],
          source_prefix: 'karya://workers/'
        },
        'worker.job.started' => {
          event_type: 'io.karya.worker.job.started',
          schema_version: 'v1',
          required_keys: %w[handler job_id queue reservation_token worker_id],
          subject_key: 'job_id',
          source_prefix: 'karya://workers/'
        },
        'worker.job.succeeded' => {
          event_type: 'io.karya.worker.job.succeeded',
          schema_version: 'v1',
          required_keys: %w[handler job_id queue reservation_token worker_id],
          subject_key: 'job_id',
          source_prefix: 'karya://workers/'
        },
        'worker.job.failed' => {
          event_type: 'io.karya.worker.job.failed',
          schema_version: 'v1',
          required_keys: %w[handler job_id queue reservation_token worker_id],
          subject_key: 'job_id',
          source_prefix: 'karya://workers/'
        },
        'supervisor.child.spawned' => {
          event_type: 'io.karya.supervisor.child.spawned',
          schema_version: 'v1',
          required_keys: %w[pid worker_id],
          subject_key: 'pid',
          source_prefix: 'karya://worker-supervisors/'
        },
        'supervisor.shutdown.signal_forwarded' => {
          event_type: 'io.karya.supervisor.shutdown.signal_forwarded',
          schema_version: 'v1',
          required_keys: %w[pids signal worker_id],
          source_prefix: 'karya://worker-supervisors/'
        }
      }.freeze

      def self.supported?(event_name)
        SCHEMAS.key?(normalize_event_name(event_name))
      end

      def self.build_event(event_name:, payload:, occurred_at:, event_id:)
        schema_definition = fetch_definition(event_name)
        event_type = schema_definition.fetch(:event_type)
        schema_version = schema_definition.fetch(:schema_version)
        normalized_payload = Payload.new(payload:, schema_definition:).to_h
        schema = Schema.new(
          event_type:,
          schema_version:,
          data_schema: data_schema_for(event_type, schema_version)
        )
        Event.new(
          id: event_id,
          source: "#{schema_definition.fetch(:source_prefix)}#{normalized_payload.fetch('worker_id')}",
          schema:,
          time: occurred_at,
          subject: subject_for(schema_definition, normalized_payload),
          data: normalized_payload
        )
      end

      def self.fetch_definition(event_name)
        normalized_event_name = normalize_event_name(event_name)
        schema_definition = SCHEMAS[normalized_event_name]
        return schema_definition if schema_definition

        raise UnsupportedOutboundEventError, "unsupported outbound event #{normalized_event_name.inspect}"
      end

      def self.data_schema_for(event_type, schema_version)
        "karya://schemas/events/#{event_type}/#{schema_version}".freeze
      end

      def self.subject_for(schema_definition, normalized_payload)
        subject_key = schema_definition.fetch(:subject_key, nil)
        return nil unless subject_key

        normalized_payload.fetch(subject_key).to_s.freeze
      end

      def self.normalize_event_name(event_name)
        event_name.to_s.strip
      end

      # Validates and normalizes one supported outbound payload.
      class Payload
        def initialize(payload:, schema_definition:)
          @payload = payload
          @schema_definition = schema_definition
        end

        def to_h
          raise InvalidOutboundEventError, 'payload must be a Hash' unless payload.is_a?(Hash)

          normalized_payload = JsonHash.new(
            payload,
            error_class: InvalidOutboundEventError,
            hash_message: 'payload must be a Hash',
            value_message: 'payload values must be JSON-compatible'
          ).normalize
          validate_required_keys(normalized_payload)
          normalized_payload
        end

        private

        attr_reader :payload, :schema_definition

        def validate_required_keys(normalized_payload)
          missing_keys = schema_definition.fetch(:required_keys) - normalized_payload.keys
          return if missing_keys.empty?

          raise InvalidOutboundEventError, "payload is missing required keys: #{missing_keys.join(', ')}"
        end
      end

      private_constant :Payload
    end
  end
end
