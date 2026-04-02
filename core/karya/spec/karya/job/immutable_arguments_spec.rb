# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::Job::ImmutableArguments' do
  let(:immutable_arguments_class) { Karya::Job.const_get(:ImmutableArguments, false) }

  describe '#normalize' do
    it 'returns already-normalized hash as-is' do
      normalized = { 'key' => 'value' }.freeze
      arguments = immutable_arguments_class.new(normalized)

      result = arguments.normalize

      expect(result).to be(normalized)
    end

    it 'deeply freezes nested hash' do
      arguments = immutable_arguments_class.new(
        'user' => { 'name' => 'Alice', 'tags' => %w[admin vip] }
      )

      result = arguments.normalize

      expect(result).to be_frozen
      expect(result['user']).to be_frozen
      expect(result['user']['name']).to be_frozen
      expect(result['user']['tags']).to be_frozen
      expect(result['user']['tags'][0]).to be_frozen
    end

    it 'normalizes and freezes string keys' do
      arguments = immutable_arguments_class.new(
        :user_id => 42,
        'account_id' => 100
      )

      result = arguments.normalize

      expect(result.keys).to contain_exactly('user_id', 'account_id')
      expect(result.keys.all?(&:frozen?)).to be true
    end

    it 'strips whitespace from keys' do
      arguments = immutable_arguments_class.new(
        '  user_id  ' => 42
      )

      result = arguments.normalize

      expect(result.keys).to eq(['user_id'])
    end

    it 'raises InvalidJobAttributeError for non-hash arguments' do
      expect do
        immutable_arguments_class.new('not a hash').normalize
      end.to raise_error(Karya::InvalidJobAttributeError, 'arguments must be a Hash')
    end

    it 'raises InvalidJobAttributeError for blank key' do
      expect do
        immutable_arguments_class.new('  ' => 'value').normalize
      end.to raise_error(Karya::InvalidJobAttributeError, 'argument keys must be present')
    end

    it 'raises InvalidJobAttributeError for duplicate keys after normalization' do
      expect do
        immutable_arguments_class.new('user_id' => 1, :user_id => 2).normalize
      end.to raise_error(Karya::InvalidJobAttributeError, /duplicate argument key after normalization/)
    end

    it 'handles immutable scalar values' do
      arguments = immutable_arguments_class.new(
        'nil_value' => nil,
        'number' => 42,
        'float' => 3.14,
        'symbol' => :status,
        'true' => true,
        'false' => false
      )

      result = arguments.normalize

      expect(result['nil_value']).to be_nil
      expect(result['number']).to eq(42)
      expect(result['float']).to eq(3.14)
      expect(result['symbol']).to eq(:status)
      expect(result['true']).to be true
      expect(result['false']).to be false
    end

    it 'duplicates and freezes duplicable scalars' do
      time = Time.utc(2026, 3, 26)
      arguments = immutable_arguments_class.new(
        'timestamp' => time,
        'name' => 'Alice'
      )

      result = arguments.normalize

      expect(result['timestamp']).to eq(time)
      expect(result['timestamp']).to be_frozen
      expect(result['timestamp'].object_id).not_to eq(time.object_id)
      expect(result['name']).to eq('Alice')
      expect(result['name']).to be_frozen
    end

    it 'raises InvalidJobAttributeError for unsupported value types' do
      expect do
        immutable_arguments_class.new('object' => Object.new).normalize
      end.to raise_error(Karya::InvalidJobAttributeError, /argument values must be composed of/)
    end

    it 'raises InvalidJobAttributeError for recursive structures' do
      recursive = {}
      recursive['self'] = recursive

      expect do
        immutable_arguments_class.new(recursive).normalize
      end.to raise_error(Karya::InvalidJobAttributeError, 'arguments must not contain recursive structures')
    end

    it 'raises InvalidJobAttributeError for recursive array structures' do
      recursive = []
      recursive << recursive

      expect do
        immutable_arguments_class.new('items' => recursive).normalize
      end.to raise_error(Karya::InvalidJobAttributeError, 'arguments must not contain recursive structures')
    end
  end

  describe 'TraversalTracker' do
    let(:traversal_tracker_class) { Karya::Job.const_get(:ImmutableArguments, false).const_get(:TraversalTracker, false) }

    describe '#track' do
      it 'tracks object_id to prevent cycles' do
        tracker = traversal_tracker_class.new
        value = { 'key' => 'value' }

        tracker.track(value)

        expect do
          tracker.track(value)
        end.to raise_error(Karya::InvalidJobAttributeError, 'arguments must not contain recursive structures')
      end
    end

    describe '#around' do
      it 'tracks object during block execution and removes it after' do
        tracker = traversal_tracker_class.new
        value = { 'key' => 'value' }

        tracker.around(value) do
          expect do
            tracker.track(value)
          end.to raise_error(Karya::InvalidJobAttributeError)
        end

        expect { tracker.track(value) }.not_to raise_error
      end

      it 'removes tracking even when block raises' do
        tracker = traversal_tracker_class.new
        value = { 'key' => 'value' }

        expect do
          tracker.around(value) do
            raise StandardError, 'test error'
          end
        end.to raise_error(StandardError, 'test error')

        expect { tracker.track(value) }.not_to raise_error
      end
    end
  end

  describe 'NormalizedGraph' do
    let(:normalized_graph_class) { Karya::Job.const_get(:ImmutableArguments, false).const_get(:NormalizedGraph, false) }
    let(:immutable_scalar_checker) { ->(v) { [NilClass, Numeric, Symbol, TrueClass, FalseClass].any? { |k| v.is_a?(k) } } }
    let(:duplicable_scalar_checker) { ->(v) { [String, Time].any? { |k| v.is_a?(k) } } }

    describe '#normalized?' do
      it 'returns true for frozen hash with frozen string keys and frozen values' do
        value = { 'key' => 'value' }.freeze
        graph = normalized_graph_class.new(value,
                                           immutable_scalar_checker: immutable_scalar_checker,
                                           duplicable_scalar_checker: duplicable_scalar_checker)

        expect(graph.normalized?).to be true
      end

      it 'returns false for unfrozen hash' do
        value = { 'key' => 'value' }
        graph = normalized_graph_class.new(value,
                                           immutable_scalar_checker: immutable_scalar_checker,
                                           duplicable_scalar_checker: duplicable_scalar_checker)

        expect(graph.normalized?).to be false
      end

      it 'returns false for hash with symbol keys' do
        value = { key: 'value' }.freeze
        graph = normalized_graph_class.new(value,
                                           immutable_scalar_checker: immutable_scalar_checker,
                                           duplicable_scalar_checker: duplicable_scalar_checker)

        expect(graph.normalized?).to be false
      end

      it 'returns false for hash with unfrozen string values' do
        value = { 'key' => +'value' }.freeze # Use unary + to create mutable string
        graph = normalized_graph_class.new(value,
                                           immutable_scalar_checker: immutable_scalar_checker,
                                           duplicable_scalar_checker: duplicable_scalar_checker)

        expect(graph.normalized?).to be false
      end

      it 'returns true for deeply nested normalized structure' do
        value = { 'user' => { 'name' => 'Alice', 'tags' => ['admin'].freeze }.freeze }.freeze
        graph = normalized_graph_class.new(value,
                                           immutable_scalar_checker: immutable_scalar_checker,
                                           duplicable_scalar_checker: duplicable_scalar_checker)

        expect(graph.normalized?).to be true
      end

      it 'returns true for immutable scalars' do
        value = { 'count' => 42, 'symbol' => :status, 'nil' => nil }.freeze
        graph = normalized_graph_class.new(value,
                                           immutable_scalar_checker: immutable_scalar_checker,
                                           duplicable_scalar_checker: duplicable_scalar_checker)

        expect(graph.normalized?).to be true
      end
    end

    describe 'NormalizedKey' do
      let(:normalized_key_class) { normalized_graph_class.const_get(:NormalizedKey, false) }

      describe '#valid?' do
        it 'returns true for frozen non-blank string' do
          key = normalized_key_class.new('user_id')
          expect(key.valid?).to be true
        end

        it 'returns false for unfrozen string' do
          key = normalized_key_class.new(+'user_id') # Use unary + to create mutable string
          expect(key.valid?).to be false
        end

        it 'returns false for symbol' do
          key = normalized_key_class.new(:user_id)
          expect(key.valid?).to be false
        end

        it 'returns false for string with leading/trailing whitespace' do
          key = normalized_key_class.new(' user_id ')
          expect(key.valid?).to be false
        end

        it 'returns false for empty string' do
          key = normalized_key_class.new('')
          expect(key.valid?).to be false
        end

        it 'returns false for blank string' do
          key = normalized_key_class.new('   ')
          expect(key.valid?).to be false
        end
      end
    end
  end
end
