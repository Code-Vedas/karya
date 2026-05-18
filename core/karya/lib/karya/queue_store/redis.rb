# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'redis/internal/dependency_loader'
require_relative 'internal/reference_queue_store'
require_relative 'redis/internal'

Karya::QueueStore::Redis::Internal::DependencyLoader.require_redis!

module Karya
  module QueueStore
    # Redis-backed durable queue store that persists canonical queue state in Redis.
    class Redis
      include Karya::QueueStore::Internal::ReferenceQueueStore

      module Internal
        StoreState = Karya::QueueStore::Internal::StoreState

        # Owner-local Redis journal coordinator for hot-path persistence and replay.
        class JournalSupport
          # Decoded journal event payload replayed back into the reference queue store.
          class PersistedEvent
            def initialize(payload)
              @payload = payload
            end

            def reservation_token
              arguments.fetch('reservation_token', nil)
            end

            def replay_on(owner)
              case name
              when 'enqueue' then owner.enqueue(job:, now:)
              when 'reserve'
                owner.reserve(
                  worker_id:,
                  lease_duration:,
                  now:,
                  queue:,
                  queues:,
                  handler_names:
                )
              when 'release' then owner.release(reservation_token:, now:)
              when 'start_execution' then owner.start_execution(reservation_token:, now:)
              when 'complete_execution' then owner.complete_execution(reservation_token:, now:)
              when 'fail_execution'
                owner.fail_execution(
                  reservation_token:,
                  now:,
                  failure_classification:,
                  retry_policy:
                )
              else
                raise InvalidQueueStoreOperationError, "unsupported Redis queue-store journal event: #{name.inspect}"
              end
            end

            private

            attr_reader :payload

            def arguments = payload.fetch('arguments')
            def name = payload.fetch('name')
            def failure_classification = arguments.fetch('failure_classification', nil)
            def handler_names = arguments.fetch('handler_names', nil)
            def job = arguments.fetch('job', nil)
            def lease_duration = arguments.fetch('lease_duration', nil)
            def now = arguments.fetch('now', nil)
            def queue = arguments.fetch('queue', nil)
            def queues = arguments.fetch('queues', nil)
            def retry_policy = arguments.fetch('retry_policy', nil)
            def worker_id = arguments.fetch('worker_id', nil)
          end

          def initialize(owner)
            @owner = owner
            @loaded_version = nil
            @snapshot_version = nil
            @replaying = false
          end

          def persist(event_builder:, persist_if: nil, &)
            return owner.send(:with_reference_queue_store_mutex, &) if replaying?

            persist_with_event(event_builder:, persist_if:, &)
          end

          def load_persisted_state
            current_version = current_persisted_version
            return if loaded_version == current_version

            if can_replay_incrementally?(current_version)
              apply_persisted_events((loaded_version + 1)..current_version)
              @loaded_version = current_version
              return
            end

            restore_state_snapshot
            apply_persisted_events((@snapshot_version + 1)..current_version) if @snapshot_version < current_version
            @loaded_version = current_version
          end

          def event_persisted(version)
            @loaded_version = version
            compact_snapshot_if_needed
          end

          def snapshot_persisted(version)
            previous_snapshot_version = @snapshot_version || 0
            @loaded_version = version
            @snapshot_version = version
            delete_journal_events_between(previous_snapshot_version + 1, version)
          end

          def compact_snapshot_if_needed
            loaded_version = @loaded_version
            return unless loaded_version.is_a?(Integer)

            snapshot_version = @snapshot_version || 0
            return if loaded_version - snapshot_version < Redis::HOT_PATH_COMPACTION_THRESHOLD

            payload = owner.send(:dump_state_payload, applied_version: loaded_version)
            return unless owner.send(:mutex).compact_snapshot(payload:)

            previous_snapshot_version = snapshot_version
            @snapshot_version = loaded_version
            delete_journal_events_between(previous_snapshot_version + 1, @snapshot_version)
          end

          def replaying?
            @replaying == true
          end

          private

          attr_reader :loaded_version, :owner

          def current_persisted_version
            version = owner.send(:redis_client).get(owner.send(:version_key))
            version ? Integer(version, 10) : 0
          end

          def can_replay_incrementally?(current_version)
            return false unless loaded_version
            return false if loaded_version >= current_version

            ((loaded_version + 1)..current_version).all? do |version|
              owner.send(:redis_client).get(owner.send(:event_key, version))
            end
          end

          def restore_state_snapshot
            payload = owner.send(:redis_client).get(owner.send(:state_key))
            unless payload
              owner.instance_variable_set(
                :@state,
                StoreState.new(expired_tombstone_limit: owner.send(:expired_tombstone_limit))
              )
              owner.instance_variable_set(:@reservation_token_sequence, 0)
              @snapshot_version = 0
              return
            end

            snapshot = StateSnapshot.load(payload)
            owner.instance_variable_set(:@state, snapshot.fetch(:state))
            owner.instance_variable_set(:@reservation_token_sequence, snapshot.fetch(:reservation_token_sequence))
            @snapshot_version = snapshot.fetch(:applied_version)
          end

          def apply_persisted_events(versions)
            versions.each do |version|
              payload = owner.send(:redis_client).get(owner.send(:event_key, version))
              raise InvalidQueueStoreOperationError, "missing Redis queue-store journal event for version #{version}" unless payload

              apply_persisted_event(StateSnapshot.load_payload(payload))
            end
          end

          def apply_persisted_event(event)
            persisted_event = PersistedEvent.new(event)
            with_journal_replay(reservation_token: persisted_event.reservation_token) { persisted_event.replay_on(owner) }
          end

          def with_journal_replay(reservation_token: nil)
            original_mutex = owner.send(:mutex)
            original_token_generator = owner.send(:token_generator)
            @replaying = true
            owner.instance_variable_set(:@mutex, Karya::QueueStore::Internal::ReferenceQueueStore::Internal::ReadOnlyMutex.new)
            owner.instance_variable_set(:@token_generator, -> { reservation_token.sub(/:\d+\z/, '') }) if reservation_token
            yield
          ensure
            owner.instance_variable_set(:@token_generator, original_token_generator)
            owner.instance_variable_set(:@mutex, original_mutex)
            @replaying = false
          end

          def delete_journal_events_between(start_version, end_version)
            return if start_version > end_version

            (start_version..end_version).each do |event_version|
              owner.send(:redis_client).del(owner.send(:event_key, event_version))
            end
          end

          def persist_with_event(event_builder:, persist_if: nil, &)
            owner.send(:mutex).synchronize_with_event(event_builder:, persist_if:) do
              owner.send(:with_reference_queue_store_mutex, &)
            end
          end

          def restore_authoritative_state_after_failure
            @loaded_version = nil
            @snapshot_version = nil
            load_persisted_state
            nil
          rescue StandardError
            nil
          end
        end
      end

      DEFAULT_NAMESPACE = 'karya'
      DEFAULT_EXPIRED_TOMBSTONE_LIMIT = Karya::QueueStore::Internal::ReferenceQueueStore::DEFAULT_EXPIRED_TOMBSTONE_LIMIT
      DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT = Karya::QueueStore::Internal::ReferenceQueueStore::DEFAULT_COMPLETED_BATCH_RETENTION_LIMIT
      DEFAULT_MAX_BATCH_SIZE = Karya::QueueStore::Internal::ReferenceQueueStore::DEFAULT_MAX_BATCH_SIZE
      RESERVE_QUEUES_ERROR_MESSAGE = Karya::QueueStore::Internal::ReferenceQueueStore::RESERVE_QUEUES_ERROR_MESSAGE
      HOT_PATH_COMPACTION_THRESHOLD = 128
      private_constant :Internal

      # Normalizes required non-empty Redis string configuration values.
      class PresentString
        def initialize(value)
          @value = value
        end

        def normalize
          return unless value.is_a?(String)

          normalized_value = value.strip
          normalized_value unless normalized_value.empty?
        end

        private

        attr_reader :value
      end

      def enqueue(job:, now:)
        event_builder = lambda do |_result|
          {
            'name' => 'enqueue',
            'arguments' => {
              'job' => job,
              'now' => now
            }
          }
        end

        journal_support.persist(event_builder:) { super }
      end

      def reserve(worker_id:, lease_duration:, now:, queue: nil, queues: nil, handler_names: nil)
        initial_fingerprint = persistence_relevant_state_fingerprint
        event_builder = lambda do |result|
          {
            'name' => 'reserve',
            'arguments' => {
              'worker_id' => worker_id,
              'lease_duration' => lease_duration,
              'now' => now,
              'queue' => queue,
              'queues' => queues,
              'handler_names' => handler_names,
              'reservation_token' => result&.token
            }
          }
        end

        journal_support.persist(
          event_builder:,
          persist_if: ->(result) { result || initial_fingerprint != persistence_relevant_state_fingerprint }
        ) do
          super
        end
      end

      def release(reservation_token:, now:)
        event_builder = lambda do |_result|
          {
            'name' => 'release',
            'arguments' => {
              'reservation_token' => reservation_token,
              'now' => now
            }
          }
        end

        journal_support.persist(event_builder:) { super }
      end

      def start_execution(reservation_token:, now:)
        event_builder = lambda do |_result|
          {
            'name' => 'start_execution',
            'arguments' => {
              'reservation_token' => reservation_token,
              'now' => now
            }
          }
        end

        journal_support.persist(event_builder:) { super }
      end

      def complete_execution(reservation_token:, now:)
        event_builder = lambda do |_result|
          {
            'name' => 'complete_execution',
            'arguments' => {
              'reservation_token' => reservation_token,
              'now' => now
            }
          }
        end

        journal_support.persist(event_builder:) { super }
      end

      def fail_execution(reservation_token:, now:, failure_classification:, retry_policy: nil)
        event_builder = lambda do |_result|
          {
            'name' => 'fail_execution',
            'arguments' => {
              'reservation_token' => reservation_token,
              'now' => now,
              'failure_classification' => failure_classification,
              'retry_policy' => retry_policy
            }
          }
        end

        journal_support.persist(event_builder:) { super }
      end

      def initialize(url:, namespace: DEFAULT_NAMESPACE, **options)
        @url = normalize_url(url)
        @namespace = normalize_namespace(namespace)
        raise InvalidQueueStoreOperationError, 'token_generator is managed internally by Karya::QueueStore::Redis' if options.key?(:token_generator)

        configure_reference_queue_store(
          initializer_options_class: Karya::QueueStore::Internal::InitializerOptions,
          store_state_class: Internal::StoreState,
          **options,
          token_generator: -> { SecureRandom.uuid }
        )
        @mutex = Internal::PersistenceMutex.new(
          redis: redis_client,
          owner: self,
          state_key:,
          lock_key:,
          version_key:
        )
      end

      private

      attr_reader :mutex, :namespace, :reservation_token_sequence, :token_generator, :url

      private_constant :PresentString

      def normalize_url(value)
        normalized_value = PresentString.new(value).normalize
        return normalized_value if normalized_value

        raise InvalidQueueStoreOperationError, 'url must be a non-empty String'
      end

      def normalize_namespace(value)
        normalized_value = PresentString.new(value).normalize
        return normalized_value if normalized_value

        raise InvalidQueueStoreOperationError, 'namespace must be a non-empty String'
      end

      def load_persisted_state = journal_support.load_persisted_state

      def dump_state_payload(applied_version:)
        Internal::StateSnapshot.dump(
          state:,
          reservation_token_sequence:,
          applied_version:
        )
      end

      class << self
        private

        def dump_event_payload(event) = Internal::StateSnapshot.dump_payload(event)
      end

      def dump_event_payload(event) = self.class.send(:dump_event_payload, event)

      def with_reference_queue_store_mutex
        original_mutex = @mutex
        @mutex = Karya::QueueStore::Internal::ReferenceQueueStore::Internal::ReadOnlyMutex.new
        yield
      ensure
        @mutex = original_mutex
      end

      def can_replay_incrementally?(current_version) = journal_support.send(:can_replay_incrementally?, current_version)
      def apply_persisted_events(versions) = journal_support.send(:apply_persisted_events, versions)
      def apply_persisted_event(event) = journal_support.send(:apply_persisted_event, event)
      def with_journal_replay(reservation_token: nil, &) = journal_support.send(:with_journal_replay, reservation_token:, &)
      def event_persisted(version) = journal_support.event_persisted(version)
      def snapshot_persisted(version) = journal_support.snapshot_persisted(version)
      def compact_snapshot_if_needed = journal_support.compact_snapshot_if_needed
      def restore_authoritative_state_after_failure = journal_support.send(:restore_authoritative_state_after_failure)

      def redis_client
        @redis_client ||= ::Redis.new(url:)
      end

      def state_key
        "#{namespace}:queue_store:state"
      end

      def lock_key
        "#{namespace}:queue_store:lock"
      end

      def version_key
        "#{namespace}:queue_store:version"
      end

      def event_key(version)
        "#{namespace}:queue_store:event:#{version}"
      end

      def journal_support
        @journal_support ||= Internal::JournalSupport.new(self)
      end
    end
  end
end
