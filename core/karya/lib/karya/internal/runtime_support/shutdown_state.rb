# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'monitor'

module Karya
  module Internal
    module RuntimeSupport
      # Shared shutdown state machine for normal, drain, and force-stop transitions.
      class ShutdownState
        NORMAL = :normal
        DRAINING = :draining
        FORCE_STOP = :force_stop

        def initialize
          @state = NORMAL
          @pre_execution_monitor = Monitor.new
        end

        def advance
          @pre_execution_monitor.synchronize do
            return if @state == FORCE_STOP

            @state = @state == DRAINING ? FORCE_STOP : DRAINING
          end
        end

        def normal?
          @pre_execution_monitor.synchronize { @state == NORMAL }
        end

        def draining?
          @pre_execution_monitor.synchronize { @state == DRAINING }
        end

        def force_stop?
          @pre_execution_monitor.synchronize { @state == FORCE_STOP }
        end

        def stop_polling?
          @pre_execution_monitor.synchronize { @state != NORMAL }
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
end
