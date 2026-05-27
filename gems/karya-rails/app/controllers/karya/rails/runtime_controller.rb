# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Rails
    # Serves runtime, readiness, and operator payloads from the mounted Rails engine.
    class RuntimeController < ApplicationController
      skip_before_action :authorize_operator_request, only: %i[health readiness]

      def health
        render json: Karya::Rails.health_payload
      end

      def readiness
        render json: Karya::Rails.readiness_payload
      end

      def operator
        render json: Karya::Rails.operator_payload(mount_path: request.script_name.presence || Karya::Rails::DEFAULT_MOUNT_PATH)
      end
    end
  end
end
