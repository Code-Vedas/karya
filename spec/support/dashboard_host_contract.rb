# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module DashboardHostContract
  def expect_dashboard_document(document, mount_path:, title:)
    expect(document).to include('<!DOCTYPE html>')
    expect(document).to include("<title>#{title}</title>")
    expect(document).to include('id="karya-dashboard-root"')
    expect(document).to include(%(data-karya-mount-path="#{mount_path}"))
    expect(document).to match(%r{<script type="module" src="(?:/[^"]+)?/assets/})
    expect(document).to match(%r{<link rel="stylesheet" href="(?:/[^"]+)?/assets/})
  end
end

RSpec.configure do |config|
  config.include DashboardHostContract
end
