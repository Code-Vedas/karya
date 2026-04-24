# frozen_string_literal: true

RSpec.describe 'Karya::Worker::MethodDispatcher' do
  let(:method_dispatcher_class) { Karya::Worker.const_get(:MethodDispatcher, false) }

  it 'dispatches positional hash handlers' do
    result = method_dispatcher_class.new(parameters: [%i[req payload]]).call(arguments: { 'account_id' => 42 }) do |mode, payload|
      [mode, payload]
    end

    expect(result).to eq([:positional_hash, { 'account_id' => 42 }])
  end

  it 'dispatches keyword handlers with symbolized keys' do
    result = method_dispatcher_class.new(parameters: [%i[keyreq account_id]]).call(arguments: { 'account_id' => 42 }) do |mode, payload|
      [mode, payload]
    end

    expect(result).to eq([:keywords, { account_id: 42 }])
  end

  it 'dispatches no-argument handlers when arguments are empty' do
    result = method_dispatcher_class.new(parameters: []).call(arguments: {}) do |mode, payload|
      [mode, payload]
    end

    expect(result).to eq([:none, nil])
  end

  it 'rejects unexpected keyword arguments' do
    dispatcher = method_dispatcher_class.new(parameters: [%i[keyreq account_id]])

    expect do
      dispatcher.call(arguments: { 'account_id' => 42, 'extra' => true }) { nil }
    end.to raise_error(Karya::InvalidWorkerConfigurationError, 'handler received unexpected argument keys: extra')
  end
end
