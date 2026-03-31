# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'monitor'

module Karya
  class Worker
    # Tracks child-worker shutdown transitions across normal, drain, and force-stop states.
    class ShutdownController
      NORMAL = :normal
      DRAINING = :draining
      FORCE_STOP = :force_stop

      def self.inactive
        @inactive ||= InactiveShutdownController.new
      end

      def initialize
        @state = NORMAL
        @pre_execution_monitor = Monitor.new
      end

      def advance
        @pre_execution_monitor.synchronize do
          return if force_stop?

          @state = draining? ? FORCE_STOP : DRAINING
        end
      end

      def draining?
        @state == DRAINING
      end

      def force_stop?
        @state == FORCE_STOP
      end

      def stop_polling?
        draining? || force_stop?
      end

      def stop_before_reserve?
        stop_polling?
      end

      def stop_after_reserve?
        stop_polling?
      end

      def stop_after_iteration?
        stop_polling?
      end

      def synchronize_pre_execution(&)
        @pre_execution_monitor.synchronize(&)
      end
    end
  end
end
