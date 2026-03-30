# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  # Raised when a requested constant path cannot be resolved.
  class ConstantResolutionError < Error; end

  # Resolves Ruby constants from explicit string paths such as "BillingJob".
  class ConstantResolver
    def initialize(name)
      @name = name
    end

    def resolve
      constant_names.reduce(Object) { |scope, constant_name| scope.const_get(constant_name, false) }
    rescue NameError => e
      raise ConstantResolutionError, "could not resolve handler constant #{name.inspect}: #{e.message}"
    end

    private

    attr_reader :name

    def constant_names
      string = name.to_s
      raise NameError, 'constant path must not be blank' if string.strip.empty?

      segments = string.split('::', -1)
      raise NameError, 'constant path must not start with ::' if segments.first.empty?
      raise NameError, 'constant path must not end with ::' if segments.last.empty?
      raise NameError, 'constant path must not contain empty segments' if segments.any?(&:empty?)

      segments
    end
  end
end
