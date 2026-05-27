# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'base'
require_relative 'framework_job/argument_codec'
require_relative 'framework_job/base'
require_relative 'framework_job/configuration'
require_relative 'framework_job/discovery'
require_relative 'framework_job/runtime_options'
require_relative 'framework_job/worker_runner'

module Karya
  # Shared framework-native job authoring support.
  module FrameworkJob
  end
end
