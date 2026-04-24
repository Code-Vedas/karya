# frozen_string_literal: true

RSpec.describe 'Karya::WorkerSupervisor::MaxIterationsSetting' do
  let(:max_iterations_setting_class) { Karya::WorkerSupervisor.const_get(:MaxIterationsSetting, false) }

  it 'treats nil as unlimited' do
    expect(max_iterations_setting_class.new(nil).normalize).to eq(:unlimited)
  end

  it 'normalizes bounded iteration counts through the shared iteration limit' do
    expect(max_iterations_setting_class.new(3).normalize).to eq(3)
  end
end
