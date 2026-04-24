# frozen_string_literal: true

RSpec.describe 'Karya::Worker::PerformExecution' do
  let(:perform_execution_class) { Karya::Worker.const_get(:PerformExecution, false) }
  let(:handler_class) do
    Class.new do
      attr_reader :received

      def perform(account_id:)
        @received = account_id
      end
    end
  end

  it 'dispatches keyword arguments through handler perform' do
    handler = handler_class.new

    perform_execution_class.new(handler).call(arguments: { 'account_id' => 42 })

    expect(handler.received).to eq(42)
  end
end
