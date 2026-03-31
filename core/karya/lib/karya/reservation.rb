# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'base'
require_relative 'reservation/attributes'

module Karya
  # Raised when reservation attributes are invalid.
  class InvalidReservationAttributeError < Error; end

  # Immutable value object representing a temporary lease on a queued job.
  class Reservation
    attr_reader :expires_at, :job_id, :queue, :reserved_at, :token, :worker_id

    def initialize(**attributes)
      normalized_attributes = Attributes.new(attributes).to_h

      @token = normalized_attributes.fetch(:token)
      @job_id = normalized_attributes.fetch(:job_id)
      @queue = normalized_attributes.fetch(:queue)
      @worker_id = normalized_attributes.fetch(:worker_id)
      @reserved_at = normalized_attributes.fetch(:reserved_at)
      @expires_at = normalized_attributes.fetch(:expires_at)

      freeze
    end

    def expired?(now)
      current_time = TimestampNormalizer.new(:now, now).normalize
      expires_at <= current_time
    end

    private_constant :Attributes
  end
end
