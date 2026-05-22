# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Rails
    # Base class for framework-native Rails jobs executed by Karya workers.
    class Job < Karya::FrameworkJob::Base
      abstract!
    end
  end
end
