# frozen_string_literal: true

RSpec.describe 'Karya::Worker::ShutdownController' do
  let(:shutdown_controller_class) { Karya::Worker.const_get(:ShutdownController, false) }

  it 'memoizes the inactive shutdown controller' do
    inactive_shutdown_controller_class = Karya::Worker.const_get(:InactiveShutdownController, false)

    expect(shutdown_controller_class.inactive).to be_a(inactive_shutdown_controller_class)
    expect(shutdown_controller_class.inactive).to equal(shutdown_controller_class.inactive)
  end
end
