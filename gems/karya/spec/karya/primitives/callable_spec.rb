# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Primitives::Callable do
  subject(:callable) { described_class.new(name, value, error_class:) }

  let(:name) { :handler }
  let(:error_class) { ArgumentError }

  describe '#normalize' do
    context 'with valid callable objects' do
      it 'returns a Proc' do
        value = proc { 'test' }
        result = described_class.new(name, value, error_class:).normalize
        expect(result).to eq(value)
      end

      it 'returns a Lambda' do
        value = -> { 'test' }
        result = described_class.new(name, value, error_class:).normalize
        expect(result).to eq(value)
      end

      it 'returns a Method object' do
        value = method(:puts)
        result = described_class.new(name, value, error_class:).normalize
        expect(result).to eq(value)
      end

      it 'returns a custom object with #call method' do
        callable_object = Class.new do
          def call
            'custom call'
          end
        end.new

        result = described_class.new(name, callable_object, error_class:).normalize
        expect(result).to eq(callable_object)
      end
    end

    context 'with invalid callable objects' do
      it 'raises error for String' do
        expect do
          described_class.new(name, 'not_callable', error_class:).normalize
        end.to raise_error(ArgumentError, 'handler must respond to #call')
      end

      it 'raises error for Integer' do
        expect do
          described_class.new(name, 42, error_class:).normalize
        end.to raise_error(ArgumentError, 'handler must respond to #call')
      end

      it 'raises error for nil' do
        expect do
          described_class.new(name, nil, error_class:).normalize
        end.to raise_error(ArgumentError, 'handler must respond to #call')
      end

      it 'raises error for Array' do
        expect do
          described_class.new(name, [], error_class:).normalize
        end.to raise_error(ArgumentError, 'handler must respond to #call')
      end

      it 'raises error for Hash' do
        expect do
          described_class.new(name, {}, error_class:).normalize
        end.to raise_error(ArgumentError, 'handler must respond to #call')
      end

      it 'raises error for object without #call method' do
        non_callable = Object.new
        expect do
          described_class.new(name, non_callable, error_class:).normalize
        end.to raise_error(ArgumentError, 'handler must respond to #call')
      end
    end

    context 'with custom error class' do
      let(:error_class) { StandardError }

      it 'raises the custom error class' do
        expect do
          described_class.new(name, 'not_callable', error_class:).normalize
        end.to raise_error(StandardError, 'handler must respond to #call')
      end
    end

    context 'with custom name' do
      let(:name) { :callback }

      it 'includes the custom name in error message' do
        expect do
          described_class.new(name, 'not_callable', error_class:).normalize
        end.to raise_error(ArgumentError, 'callback must respond to #call')
      end
    end
  end
end
