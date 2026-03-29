# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  # Resolves Ruby constants from explicit string paths such as "BillingJob".
  class ConstantResolver
    def initialize(name)
      @name = name
    end

    def resolve
      constant_names.reduce(Object) { |scope, constant_name| scope.const_get(constant_name) }
    rescue NameError => e
      raise Thor::Error, "could not resolve handler constant #{name.inspect}: #{e.message}"
    end

    private

    attr_reader :name

    def constant_names
      name.split('::').reject(&:empty?)
    end
  end
end
