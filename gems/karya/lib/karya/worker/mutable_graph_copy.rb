# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class Worker
    # Produces mutable copies of normalized immutable argument graphs for handler dispatch.
    class MutableGraphCopy
      def self.call(value)
        case value
        when Hash
          duplicate_hash(value)
        when Array
          duplicate_array(value)
        when String, Time
          value.dup
        else
          value
        end
      end

      def self.duplicate_hash(value)
        value.each_with_object({}) do |(key, nested_value), duplicated|
          duplicated[key.dup] = call(nested_value)
        end
      end

      def self.duplicate_array(value)
        value.map { |nested_value| call(nested_value) }
      end

      private_class_method :new
      private_class_method :duplicate_array, :duplicate_hash
    end
  end
end
