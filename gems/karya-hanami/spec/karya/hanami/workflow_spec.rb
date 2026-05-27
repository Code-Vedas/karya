# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Hanami::Workflow do
  it 'delegates workflow operations through the shared facade' do
    facade = instance_double(Karya::Internal::FrameworkWorkflow::Facade, catalog: :catalog)
    allow(described_class).to receive(:facade).and_return(facade)

    expect(described_class.catalog).to eq(:catalog)
  end

  it 'memoizes the workflow facade with the Hanami configuration provider' do
    allow(Karya).to receive(:queue_store).and_return(instance_double(Karya::QueueStore::Base))
    allow(Karya::Hanami).to receive(:configuration).and_return(:configuration)
    described_class.instance_variable_set(:@facade, nil)
    facade = described_class.send(:facade)

    expect(facade).to be_a(Karya::Internal::FrameworkWorkflow::Facade)
    expect(facade.send(:configuration_provider).call).to eq(:configuration)
  ensure
    described_class.instance_variable_set(:@facade, nil)
  end
end
