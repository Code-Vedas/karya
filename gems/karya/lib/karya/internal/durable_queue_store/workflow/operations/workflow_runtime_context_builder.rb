# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Internal
    module DurableQueueStore
      module Operations
        # Rebuilds workflow-visible rows after optional recovery for one workflow operation.
        class WorkflowRuntimeContextBuilder
          def initialize(context:, now:, host:, recover: true)
            @context = context
            @now = now
            @host = host
            @recover = recover
          end

          attr_reader :context, :now, :host, :recover

          def call
            recovery =
              if recover
                host.send(:recovery_pass, context, now)
              else
                { expired_jobs: [], recovered_reserved_jobs: [], recovered_running_jobs: [], plan: MutationPlan.new, changed: false }
              end
            [recovered_rows(recovery), recovery]
          end

          private

          def recovered_rows(recovery)
            namespace = context.namespace
            recovered_jobs = recovery.values_at(:expired_jobs, :recovered_reserved_jobs, :recovered_running_jobs).flatten
            Operations::RecoveredRowsApplier.new(
              namespace:,
              rows: context.rows.merge(namespace:),
              jobs: recovered_jobs
            ).apply
          end
        end
      end
    end
  end
end
