# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Workflow::Dependency do
  it 'normalizes both step ids and freezes the dependency' do
    dependency = described_class.new(step_id: ' emit_receipt ', depends_on_step_id: :capture_payment)

    expect(dependency.step_id).to eq('emit_receipt')
    expect(dependency.depends_on_step_id).to eq('capture_payment')
    expect(dependency).to be_frozen
  end
end
