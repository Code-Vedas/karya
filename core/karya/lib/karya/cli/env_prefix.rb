# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  class CLI < Thor
    # Normalizes worker-specific env prefixes used for process/thread settings.
    class EnvPrefix
      def initialize(value)
        @value = value
      end

      def normalize
        normalized = value.to_s.strip.gsub(/[^a-zA-Z0-9]+/, '_').gsub(/\A_+|_+\z/, '').upcase
        return normalized unless normalized.empty?

        raise InvalidWorkerSupervisorConfigurationError,
              'Invalid value for --env-prefix: prefix must contain at least one alphanumeric character.'
      end

      private

      attr_reader :value
    end
  end
end
