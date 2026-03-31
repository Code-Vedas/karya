# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'monitor'

module Karya
  class Worker
    # Null shutdown controller used by one-shot worker entrypoints like `work_once`.
    class InactiveShutdownController
      def initialize
        @pre_execution_monitor = Monitor.new
      end

      def force_stop?
        false
      end

      def stop_polling?
        false
      end

      def stop_before_reserve?
        false
      end

      def stop_after_reserve?
        false
      end

      def stop_after_iteration?
        false
      end

      def synchronize_pre_execution(&)
        @pre_execution_monitor.synchronize(&)
      end
    end
  end
end
