# frozen_string_literal: true

RSpec.describe 'Karya::Worker::CallableExecution' do
  let(:callable_execution_class) { Karya::Worker.const_get(:CallableExecution, false) }

  it 'dispatches keyword arguments through handler call' do
    received = nil
    handler = ->(account_id:) { received = account_id }

    callable_execution_class.new(handler).call(arguments: { 'account_id' => 42 })

    expect(received).to eq(42)
  end

  it 'dispatches positional hash arguments through handler call' do
    received = nil
    handler = lambda do |payload|
      received = payload
    end

    callable_execution_class.new(handler).call(arguments: { 'account_id' => 42 })

    expect(received).to eq({ 'account_id' => 42 })
  end
end
