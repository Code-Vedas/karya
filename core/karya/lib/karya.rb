# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'karya/version'
require_relative 'karya/cli'

# Karya module serves as the namespace for all classes and modules related to the Karya gem.
module Karya
  # Error is the base class for all exceptions raised by Karya.
  class Error < StandardError; end
end
