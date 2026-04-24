# frozen_string_literal: true

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
