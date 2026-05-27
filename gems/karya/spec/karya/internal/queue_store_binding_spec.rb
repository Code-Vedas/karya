# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::QueueStoreBinding do
  after do
    Karya.send(:remove_instance_variable, :@queue_store) if Karya.instance_variable_defined?(:@queue_store)
  end

  it 'ignores a nil snapshot' do
    queue_store = instance_double(Karya::QueueStore::Base)
    Karya.configure_queue_store(queue_store)

    described_class.restore(nil)

    expect(Karya.instance_variable_get(:@queue_store)).to equal(queue_store)
  end

  it 'captures and restores an undefined queue-store binding' do
    Karya.send(:remove_instance_variable, :@queue_store) if Karya.instance_variable_defined?(:@queue_store)
    snapshot = described_class.capture
    Karya.configure_queue_store(instance_double(Karya::QueueStore::Base))

    described_class.restore(snapshot)

    expect(Karya.instance_variable_defined?(:@queue_store)).to be(false)
  end

  it 'captures and restores a defined nil queue-store binding' do
    Karya.configure_queue_store(nil)
    snapshot = described_class.capture
    Karya.configure_queue_store(instance_double(Karya::QueueStore::Base))

    described_class.restore(snapshot)

    expect(Karya.instance_variable_defined?(:@queue_store)).to be(true)
    expect(Karya.instance_variable_get(:@queue_store)).to be_nil
  end

  it 'captures and restores a configured queue store object' do
    queue_store = instance_double(Karya::QueueStore::Base)
    Karya.configure_queue_store(queue_store)
    snapshot = described_class.capture
    Karya.configure_queue_store(instance_double(Karya::QueueStore::Base))

    described_class.restore(snapshot)

    expect(Karya.instance_variable_get(:@queue_store)).to equal(queue_store)
  end
end
