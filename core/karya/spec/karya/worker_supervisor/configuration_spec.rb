# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::WorkerSupervisor::Configuration' do
  let(:configuration_class) { Karya::WorkerSupervisor.const_get(:Configuration, false) }

  it 'treats nil max_iterations as unlimited for supervisor configuration' do
    configuration = configuration_class.new(
      worker_id: 'worker-supervisor',
      queues: ['billing'],
      handlers: { 'billing_sync' => -> {} },
      lease_duration: 30,
      max_iterations: nil
    )

    expect(configuration.max_iterations).to eq(:unlimited)
    expect(configuration.bounded_run?).to be(false)
  end

  it 'normalizes optional default_execution_timeout' do
    configuration = configuration_class.new(
      worker_id: 'worker-supervisor',
      queues: ['billing'],
      handlers: { 'billing_sync' => -> {} },
      lease_duration: 30,
      default_execution_timeout: 12
    )

    expect(configuration.default_execution_timeout).to eq(12)
  end
end
