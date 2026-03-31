# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::JobLifecycle do
  around do |example|
    described_class.send(:clear_extensions!)
    example.run
    described_class.send(:clear_extensions!)
  end

  describe 'private helpers' do
    it 'does not expose cache invalidation as a public module API' do
      expect(described_class.respond_to?(:invalidate_caches)).to be(false)
      expect(described_class.respond_to?(:invalidate_caches, true)).to be(true)
    end

    it 'does not expose extension reset as a public module API' do
      expect(described_class.respond_to?(:clear_extensions!)).to be(false)
      expect(described_class.respond_to?(:clear_extensions!, true)).to be(true)
    end

    it 'does not expose raw state normalization as a public module API' do
      expect(described_class.respond_to?(:normalize_state_name)).to be(false)
      expect(described_class.respond_to?(:normalize_state_name, true)).to be(true)
    end
  end

  describe '.instance_variable_get' do
    it 'returns extension_state_names for @extension_state_names' do
      described_class.register_state(:custom_state)
      result = described_class.instance_variable_get(:@extension_state_names)
      expect(result).to include('custom_state')
    end

    it 'returns extension_terminal_state_names for @extension_terminal_state_names' do
      described_class.register_state(:custom_terminal, terminal: true)
      result = described_class.instance_variable_get(:@extension_terminal_state_names)
      expect(result).to include('custom_terminal')
    end

    it 'returns extension_transitions for @extension_transitions' do
      described_class.register_state(:from_state)
      described_class.register_state(:to_state)
      described_class.register_transition(from: :from_state, to: :to_state)
      result = described_class.instance_variable_get(:@extension_transitions)
      expect(result).to be_a(Hash)
      expect(result).to have_key('from_state')
    end

    it 'returns mutex for @mutex' do
      result = described_class.instance_variable_get(:@mutex)
      expect(result).to be_a(Thread::Mutex)
    end

    it 'calls super for unknown instance variables' do
      result = described_class.instance_variable_get(:@unknown_variable)
      expect(result).to be_nil
    end
  end

  describe 'private module_function helpers' do
    it 'normalize_state_locked is callable as module function' do
      expect(described_class.respond_to?(:normalize_state_locked, true)).to be(true)
      result = described_class.send(:normalize_state_locked, :queued)
      expect(result).to eq('queued')
    end

    it 'state_names_locked is callable as module function' do
      expect(described_class.respond_to?(:state_names_locked, true)).to be(true)
      result = described_class.send(:state_names_locked)
      expect(result).to be_a(Array)
    end

    it 'transition_names_locked is callable as module function' do
      expect(described_class.respond_to?(:transition_names_locked, true)).to be(true)
      result = described_class.send(:transition_names_locked)
      expect(result).to be_a(Hash)
    end

    it 'terminal_state_names_locked is callable as module function' do
      expect(described_class.respond_to?(:terminal_state_names_locked, true)).to be(true)
      result = described_class.send(:terminal_state_names_locked)
      expect(result).to be_a(Array)
    end

    it 'invalidate_caches is callable as module function' do
      expect(described_class.respond_to?(:invalidate_caches, true)).to be(true)
      expect { described_class.send(:invalidate_caches) }.not_to raise_error
    end

    it 'normalize_state_name is callable as module function' do
      expect(described_class.respond_to?(:normalize_state_name, true)).to be(true)
      result = described_class.send(:normalize_state_name, 'queued')
      expect(result).to eq('queued')
    end

    it 'validate_state_locked! is callable as module function' do
      expect(described_class.respond_to?(:validate_state_locked!, true)).to be(true)
      expect { described_class.send(:validate_state_locked!, 'queued') }.not_to raise_error
    end

    it 'extension_state_name? is callable as module function' do
      expect(described_class.respond_to?(:extension_state_name?, true)).to be(true)
      result = described_class.send(:extension_state_name?, 'queued')
      expect(result).to be(false)
    end

    it 'public_state is callable as module function' do
      expect(described_class.respond_to?(:public_state, true)).to be(true)
      result = described_class.send(:public_state, 'queued')
      expect(result).to eq(:queued)
    end

    it 'transition_values is callable as module function' do
      expect(described_class.respond_to?(:transition_values, true)).to be(true)
      result = described_class.send(:transition_values, %w[queued running])
      expect(result).to be_a(Array)
    end

    it 'lowercase_letter? is callable as module function' do
      expect(described_class.respond_to?(:lowercase_letter?, true)).to be(true)
      expect(described_class.send(:lowercase_letter?, 'a')).to be(true)
      expect(described_class.send(:lowercase_letter?, 'A')).to be(false)
    end

    it 'digit? is callable as module function' do
      expect(described_class.respond_to?(:digit?, true)).to be(true)
      expect(described_class.send(:digit?, '5')).to be(true)
      expect(described_class.send(:digit?, 'a')).to be(false)
    end

    it 'raise_blank_state_error! is callable as module function' do
      expect(described_class.respond_to?(:raise_blank_state_error!, true)).to be(true)
      expect { described_class.send(:raise_blank_state_error!) }.to raise_error(Karya::JobLifecycle::InvalidJobStateError)
    end
  end
end
