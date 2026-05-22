# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::FrameworkJob::RuntimeOptions do
  describe '.compact' do
    it 'removes nil values and preserves false values' do
      expect(described_class.compact(processes: 2, stop_when_idle: false, state_file: nil)).to eq(
        processes: 2,
        stop_when_idle: false
      )
    end
  end

  describe '.from_env' do
    it 'parses supported runtime options from environment variables' do
      options = described_class.from_env(
        'KARYA_PROCESSES' => '2',
        'KARYA_THREADS' => '4',
        'KARYA_WORKER_ID' => 'billing-1',
        'KARYA_LEASE_DURATION' => '30',
        'KARYA_POLL_INTERVAL' => '1.5',
        'KARYA_DEFAULT_EXECUTION_TIMEOUT' => '15',
        'KARYA_STATE_FILE' => 'tmp/karya.json',
        'KARYA_ENV_PREFIX' => 'billing',
        'KARYA_MAX_ITERATIONS' => '10',
        'KARYA_STOP_WHEN_IDLE' => 'false'
      )

      expect(options).to eq(
        processes: 2,
        threads: 4,
        worker_id: 'billing-1',
        lease_duration: 30.0,
        poll_interval: 1.5,
        default_execution_timeout: 15.0,
        state_file: 'tmp/karya.json',
        env_prefix: 'billing',
        max_iterations: 10,
        stop_when_idle: false
      )
    end

    it 'rejects invalid boolean values' do
      expect do
        described_class.from_env('KARYA_STOP_WHEN_IDLE' => 'maybe')
      end.to raise_error(ArgumentError, /invalid boolean value/)
    end

    it 'parses truthy booleans' do
      expect(described_class.from_env('KARYA_STOP_WHEN_IDLE' => 'true')).to eq(stop_when_idle: true)
    end

    it 'returns an empty option hash for empty environment values' do
      expect(described_class.from_env({})).to eq({})
      expect(described_class.from_env('KARYA_STOP_WHEN_IDLE' => '')).to eq({})
    end
  end
end
