# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Hanami::CLI::Install do
  let(:command) { described_class.new }

  it 'installs framework files through the shared installer' do
    installer = ->(**) {}
    allow(Karya::Internal::FrameworkInstaller).to receive_messages(
      migration_kind: :sqlite,
      sequel_migration_installer: installer,
      install!: nil
    )
    allow(Dir).to receive(:pwd).and_return('/tmp/app')

    command.call(backend: 'sqlite')

    expect(Karya::Internal::FrameworkInstaller).to have_received(:install!).with(
      framework_class_name: 'Karya::Hanami',
      root_path: '/tmp/app',
      backend: 'sqlite',
      migration_kind: :sqlite,
      migration_target_dir: '/tmp/app/db/migrations',
      migration_installer: installer
    )
  end
end
