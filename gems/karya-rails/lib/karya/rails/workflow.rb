# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Rails
    # Rails-native workflow DSL and control facade.
    module Workflow
      Source = Karya::Internal::FrameworkWorkflow::Source
      extend self

      def define(...)
        facade.define(...)
      end

      def catalog
        facade.catalog
      end

      def start(...)
        facade.start(...)
      end

      def batch(...)
        facade.batch(...)
      end

      def snapshot(...)
        facade.snapshot(...)
      end

      def history(...)
        facade.history(...)
      end

      def query(...)
        facade.query(...)
      end

      def signal(...)
        facade.signal(...)
      end

      def event(...)
        facade.event(...)
      end

      def pause(...)
        facade.pause(...)
      end

      def resume(...)
        facade.resume(...)
      end

      def approve(...)
        facade.approve(...)
      end

      def reject(...)
        facade.reject(...)
      end

      def retry_steps(...)
        facade.retry_steps(...)
      end

      def dead_letter_steps(...)
        facade.dead_letter_steps(...)
      end

      def replay_steps(...)
        facade.replay_steps(...)
      end

      def retry_dead_letter_steps(...)
        facade.retry_dead_letter_steps(...)
      end

      def discard_steps(...)
        facade.discard_steps(...)
      end

      def rollback(...)
        facade.rollback(...)
      end

      def enqueue_child(...)
        facade.enqueue_child(...)
      end

      def sync_children(...)
        facade.sync_children(...)
      end

      def facade
        @facade ||= Karya::Internal::FrameworkWorkflow::Facade.new(
          configuration_provider: -> { Karya::Rails.configuration }
        )
      end
      private :facade
    end
  end
end
