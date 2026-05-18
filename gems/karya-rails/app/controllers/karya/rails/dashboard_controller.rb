# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Karya
  module Rails
    # Serves the packaged dashboard document from the mounted Rails engine.
    class DashboardController < ApplicationController
      def show
        render body: Karya::Rails.render_dashboard_page(
          mount_path: request.script_name.presence || Karya::Rails::DEFAULT_MOUNT_PATH
        ), content_type: 'text/html'
      end
    end
  end
end
