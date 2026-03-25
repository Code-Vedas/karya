# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'fileutils'
require 'rack'
require 'tmpdir'

module KaryaRodaDummyAppSupport
  module_function

  GEM_ROOT = File.expand_path('../..', __dir__)
  DUMMY_SOURCE = File.join(GEM_ROOT, 'spec', 'dummy')

  def with_dummy_app
    Dir.mktmpdir('karya-roda-') do |root|
      app_root = File.join(root, 'app')
      FileUtils.copy_entry(DUMMY_SOURCE, app_root)
      yield app_root, Rack::Builder.parse_file(File.join(app_root, 'config.ru'))
    end
  end
end
