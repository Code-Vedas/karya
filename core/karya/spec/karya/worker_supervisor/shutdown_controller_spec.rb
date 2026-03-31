# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::WorkerSupervisor::ShutdownController' do
  let(:controller_class) { Karya::WorkerSupervisor.const_get(:ShutdownController, false) }

  it 'covers shutdown controller transitions' do
    controller = controller_class.new

    expect(controller.normal?).to be(true)
    controller.advance
    expect(controller.draining?).to be(true)
    controller.advance
    expect(controller.force_stop?).to be(true)
  end

  it 'keeps force-stop as a terminal shutdown state' do
    controller = controller_class.new

    controller.advance
    controller.advance
    controller.advance

    expect(controller.force_stop?).to be(true)
  end
end
