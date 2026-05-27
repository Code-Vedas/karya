# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::Worker::InactiveShutdownController' do
  subject(:controller) { inactive_shutdown_controller_class.new }

  let(:inactive_shutdown_controller_class) { Karya::Worker.const_get(:InactiveShutdownController, false) }

  it 'never reports shutdown conditions' do
    expect(controller.force_stop?).to be(false)
    expect(controller.stop_polling?).to be(false)
    expect(controller.stop_before_reserve?).to be(false)
    expect(controller.stop_after_reserve?).to be(false)
    expect(controller.stop_after_iteration?).to be(false)
  end

  it 'synchronizes pre-execution blocks' do
    expect(controller.synchronize_pre_execution { :ok }).to eq(:ok)
  end
end
