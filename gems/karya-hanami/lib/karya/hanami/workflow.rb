# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Hanami
    # Hanami-native workflow DSL and control facade.
    module Workflow
      Source = Karya::Internal::FrameworkWorkflow::Source
      extend self

      %i[
        define catalog start batch snapshot history query signal event pause resume approve reject
        retry_steps dead_letter_steps replay_steps retry_dead_letter_steps discard_steps rollback
        enqueue_child sync_children
      ].each do |method_name|
        define_method(method_name) do |*args, **kwargs, &block|
          facade.public_send(method_name, *args, **kwargs, &block)
        end
      end

      def facade
        @facade ||= Karya::Internal::FrameworkWorkflow::Facade.new(
          configuration_provider: -> { Karya::Hanami.configuration }
        )
      end
      private :facade
    end
  end
end
