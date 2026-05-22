# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'kaal'
require 'karya/internal/kaal_delayed_scheduler'

RSpec.describe Karya::Internal::KaalDelayedScheduler do
  describe '.schedule' do
    around do |example|
      original_backend = Kaal.configuration.backend
      original_delayed_job_allowed_class_prefixes = Kaal.configuration.delayed_job_allowed_class_prefixes

      example.run
    ensure
      next unless defined?(Kaal)

      Kaal.reset_configuration!
      Kaal.configuration.backend = original_backend
      Kaal.configuration.delayed_job_allowed_class_prefixes = original_delayed_job_allowed_class_prefixes
    end

    let(:arguments) { { task: 'later' } }
    let(:created_at) { Time.utc(2026, 5, 21, 12, 0, 0) }
    let(:scheduled_at) { Time.utc(2026, 5, 21, 12, 6, 0) + Rational(123_456_789, 1_000_000_000) }

    it 'raises unsupported scheduling when Kaal is unavailable' do
      hide_const('Kaal')

      expect do
        described_class.schedule(
          queue: 'default',
          handler: 'demo',
          arguments:,
          job_id: 'future-job',
          created_at:,
          scheduled_at:
        )
      end.to raise_error(Karya::UnsupportedSchedulingError, /requires Kaal with delayed-job support/)
    end

    it 'raises unsupported scheduling when the configured backend lacks a delayed store' do
      Kaal.reset_configuration!
      Kaal.configuration.backend = Struct.new(:delayed_store).new(nil)

      expect do
        described_class.schedule(
          queue: 'default',
          handler: 'demo',
          arguments:,
          job_id: 'future-job',
          created_at:,
          scheduled_at:
        )
      end.to raise_error(Karya::UnsupportedSchedulingError, /requires Kaal with delayed-job support/)
    end

    it 'preserves the requested run_at and serialized scheduled_at values' do
      Kaal.reset_configuration!
      Kaal.configuration.backend = Kaal::Backend::MemoryAdapter.new

      receipt = described_class.schedule(
        queue: 'default',
        handler: 'demo',
        arguments:,
        job_id: 'future-job',
        created_at:,
        scheduled_at:
      )

      expect(receipt.fetch(:run_at)).to eq(scheduled_at)
      payload = Karya::Internal::DelayedEnqueueJob.deserialize_request(receipt.fetch(:args).fetch(0))
      expect(payload.fetch('scheduled_at')).to eq(scheduled_at)
    end
  end
end
