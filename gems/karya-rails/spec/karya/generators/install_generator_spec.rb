# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../rails_helper'
require 'generators/karya/install/install_generator'

RSpec.describe Karya::Generators::InstallGenerator do
  it 'installs framework files through the shared installer' do
    generator = described_class.allocate
    allow(generator).to receive_messages(
      options: { 'backend' => 'sqlite' },
      destination_root: '/tmp/app'
    )
    allow(Karya::Internal::FrameworkInstaller).to receive_messages(
      migration_kind: :sqlite,
      active_record_migration_installer: ->(**) {},
      install!: nil
    )

    generator.install_karya

    expect(Karya::Internal::FrameworkInstaller).to have_received(:install!).with(
      framework_class_name: 'Karya::Rails',
      root_path: '/tmp/app',
      backend: 'sqlite',
      migration_kind: :sqlite,
      migration_target_dir: '/tmp/app/db/migrate',
      migration_installer: kind_of(Proc)
    )
  end
end
