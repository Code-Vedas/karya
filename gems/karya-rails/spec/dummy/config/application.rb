# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require_relative 'boot'

require 'rails/all'

Bundler.require(*Rails.groups)

module KaryaRailsDummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.api_only = false
    config.autoload_lib(ignore: %w[assets tasks])
    config.generators.system_tests = nil
  end
end
