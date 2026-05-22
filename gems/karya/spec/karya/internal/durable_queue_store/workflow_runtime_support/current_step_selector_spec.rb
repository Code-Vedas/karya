# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Karya::Internal::DurableQueueStore::WorkflowRuntimeSupport::CurrentStepSelector do
  it 'prefers active steps, then ready steps, then satisfied blocked steps' do
    active_step_class = Class.new do
      def active?; end
      def ready?; end
      def blocked?; end
      def step_id; end
      def prerequisite_states; end
    end
    ready_step_class = Class.new do
      def active?; end
      def ready?; end
      def blocked?; end
      def step_id; end
      def prerequisite_states; end
    end
    blocked_step_class = Class.new do
      def active?; end
      def ready?; end
      def blocked?; end
      def step_id; end
      def prerequisite_states; end
    end

    active_step = instance_double(active_step_class, active?: true, ready?: false, blocked?: false, step_id: 'active', prerequisite_states: {})
    ready_step = instance_double(ready_step_class, active?: false, ready?: true, blocked?: false, step_id: 'ready', prerequisite_states: {})
    blocked_step = instance_double(
      blocked_step_class,
      active?: false,
      ready?: false,
      blocked?: true,
      step_id: 'blocked',
      prerequisite_states: { 'dep' => :succeeded }
    )

    expect(described_class.new(steps: [active_step]).call).to eq(['active'])
    expect(described_class.new(steps: [ready_step]).call).to eq(['ready'])
    expect(described_class.new(steps: [blocked_step]).call).to eq(['blocked'])
  end
end
