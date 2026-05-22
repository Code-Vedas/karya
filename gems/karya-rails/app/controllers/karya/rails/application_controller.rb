# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Rails
    # Base controller for the mounted Karya Rails engine.
    class ApplicationController < ActionController::Base
      protect_from_forgery with: :exception

      before_action :authorize_operator_request

      private

      def authorize_operator_request
        return if Karya::Rails.operator_access_authorized?(self)

        head :forbidden
      end

      alias authorize_operator_request! authorize_operator_request
    end
  end
end
