# frozen_string_literal: true

RSpec.describe 'Karya::Worker::HandlerExecution' do
  let(:handler_execution_class) { Karya::Worker.const_get(:HandlerExecution, false) }
  let(:callable_execution_class) { Karya::Worker.const_get(:CallableExecution, false) }
  let(:perform_execution_class) { Karya::Worker.const_get(:PerformExecution, false) }
  let(:unsupported_execution_class) { Karya::Worker.const_get(:UnsupportedExecution, false) }
  let(:callable_handler) { -> {} }
  let(:perform_handler_class) do
    Class.new do
      def perform; end
    end
  end

  it 'builds callable execution for handlers responding to call' do
    execution = handler_execution_class.build(handler: callable_handler, handler_name: 'billing_sync')

    expect(execution).to be_a(callable_execution_class)
  end

  it 'builds perform execution for handlers responding only to perform' do
    execution = handler_execution_class.build(handler: perform_handler_class.new, handler_name: 'billing_sync')

    expect(execution).to be_a(perform_execution_class)
  end

  it 'builds unsupported execution for handlers without call or perform' do
    execution = handler_execution_class.build(handler: Object.new, handler_name: 'billing_sync')

    expect(execution).to be_a(unsupported_execution_class)
  end
end
