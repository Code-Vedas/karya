# frozen_string_literal: true

RSpec.describe Karya::CLI do
  describe '.run_with_lifecycle' do
    let(:backend_boot_class) { described_class.const_get(:BackendBoot, false) }
    let(:queue_store) { instance_double(Karya::QueueStore::Base) }

    it 'runs backend lifecycle hooks around the yielded boot block' do
      lifecycle_events = []
      backend_class = Class.new do
        include Karya::Backend::Base

        define_method(:identifier) { 'test_backend' }
        define_method(:build_queue_store) { raise 'not used in this spec' }
        define_method(:before_start) { |queue_store:| lifecycle_events << [:before_start, queue_store] }
        define_method(:after_stop) { |queue_store:| lifecycle_events << [:after_stop, queue_store] }
      end
      backend = backend_class.new

      result = backend_boot_class.run_with_lifecycle(backend, queue_store) { 0 }

      expect(result).to eq(0)
      expect(lifecycle_events).to eq([[:before_start, queue_store], [:after_stop, queue_store]])
    end

    it 'does not let after_stop override a non-zero supervisor status' do
      lifecycle_events = []
      backend_class = Class.new do
        include Karya::Backend::Base

        define_method(:identifier) { 'test_backend' }
        define_method(:build_queue_store) { raise 'not used in this spec' }
        define_method(:before_start) { |queue_store:| lifecycle_events << [:before_start, queue_store] }
        define_method(:after_stop) do |queue_store:|
          lifecycle_events << [:after_stop, queue_store]
          raise 'cleanup failed'
        end
      end
      backend = backend_class.new

      expect(backend_boot_class.run_with_lifecycle(backend, queue_store) { 1 }).to eq(1)
      expect(lifecycle_events).to eq([[:before_start, queue_store], [:after_stop, queue_store]])
    end

    it 'surfaces after_stop failures when the wrapped boot succeeds' do
      backend_class = Class.new do
        include Karya::Backend::Base

        define_method(:identifier) { 'test_backend' }
        define_method(:build_queue_store) { raise 'not used in this spec' }
        define_method(:before_start) { |queue_store:| queue_store }
        define_method(:after_stop) { |queue_store:| raise "cleanup failed for #{queue_store.object_id}" }
      end
      backend = backend_class.new

      expect do
        backend_boot_class.run_with_lifecycle(backend, queue_store) { 0 }
      end.to raise_error(RuntimeError, /cleanup failed/)
    end

    it 'preserves the primary boot error when the wrapped boot raises' do
      lifecycle_events = []
      backend_class = Class.new do
        include Karya::Backend::Base

        define_method(:identifier) { 'test_backend' }
        define_method(:build_queue_store) { raise 'not used in this spec' }
        define_method(:before_start) { |queue_store:| lifecycle_events << [:before_start, queue_store] }
        define_method(:after_stop) { |queue_store:| lifecycle_events << [:after_stop, queue_store] }
      end
      backend = backend_class.new

      expect do
        backend_boot_class.run_with_lifecycle(backend, queue_store) { raise 'boot failed' }
      end.to raise_error(RuntimeError, /boot failed/)
      expect(lifecycle_events).to eq([[:before_start, queue_store], [:after_stop, queue_store]])
    end

    it 'does not call after_stop when before_start fails' do
      lifecycle_events = []
      backend_class = Class.new do
        include Karya::Backend::Base

        define_method(:identifier) { 'test_backend' }
        define_method(:build_queue_store) { raise 'not used in this spec' }
        define_method(:before_start) do |queue_store:|
          lifecycle_events << [:before_start, queue_store]
          raise 'setup failed'
        end
        define_method(:after_stop) { |queue_store:| lifecycle_events << [:after_stop, queue_store] }
      end
      backend = backend_class.new

      expect do
        backend_boot_class.run_with_lifecycle(backend, queue_store) { 0 }
      end.to raise_error(RuntimeError, /setup failed/)
      expect(lifecycle_events).to eq([[:before_start, queue_store]])
    end

    it 'returns the yielded result when no backend is configured' do
      expect(backend_boot_class.run_with_lifecycle(nil, queue_store) { 7 }).to eq(7)
    end
  end
end
