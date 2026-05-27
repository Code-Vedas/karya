# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'monitor'

module Karya
  module Internal
    # Tracks framework job subclasses by the file that defined the subclass.
    module FrameworkJobRegistry
      MONITOR = Monitor.new
      private_constant :MONITOR

      # Immutable registry entry for one discovered framework job subclass.
      Entry = Struct.new(:klass, :source_path, keyword_init: true) do
        def framework_job_class?(job_base)
          klass < job_base && !klass.abstract?
        rescue NoMethodError
          false
        end
      end

      module_function

      def register(klass, source_path:)
        synchronize do
          registry[klass] = Entry.new(klass:, source_path: normalize_source_path(source_path))
          klass
        end
      end

      def entries
        synchronize { registry.values.dup }
      end

      def reset!
        synchronize { @registry = {}.compare_by_identity }
      end

      def registry
        @registry ||= {}.compare_by_identity
      end
      private_class_method :registry

      def synchronize(&)
        MONITOR.synchronize(&)
      end
      private_class_method :synchronize

      def normalize_source_path(source_path)
        return nil unless source_path

        File.expand_path(source_path)
      end
      private_class_method :normalize_source_path
    end
  end
end
