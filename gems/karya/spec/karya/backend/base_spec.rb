# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Backend::Base do
  subject(:backend) { implementation.new }

  let(:implementation) do
    Class.new do
      include Karya::Backend::Base
    end
  end

  it 'requires identifier to be implemented' do
    expect { backend.identifier }.to raise_error(NotImplementedError, /implement #identifier/)
  end

  it 'requires build_queue_store to be implemented' do
    expect { backend.build_queue_store }.to raise_error(NotImplementedError, /implement #build_queue_store/)
  end

  it 'provides no-op lifecycle hooks by default' do
    queue_store = instance_double(Karya::QueueStore::Base)

    expect(backend.before_start(queue_store:)).to be_nil
    expect(backend.after_stop(queue_store:)).to be_nil
  end
end
