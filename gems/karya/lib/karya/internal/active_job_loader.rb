# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    # Shared ActiveJob dependency loader for compatibility entrypoints.
    module ActiveJobLoader
      module_function

      def require!
        require 'active_job'
      rescue LoadError => e
        raise LoadError, 'cannot load active_job. Add the activejob gem to use Karya::ActiveJob compatibility.', e.backtrace
      end
    end
  end
end
