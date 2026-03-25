# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'hanami'
require 'karya/hanami'

KaryaHanamiDummyApp = proc do |env|
  if env['PATH_INFO'] == '/karya'
    [
      200,
      { 'content-type' => 'text/html; charset=utf-8' },
      [Karya::Hanami.render_dashboard_page(prefix: 'admin')]
    ]
  else
    [404, { 'content-type' => 'text/plain' }, ['not found']]
  end
end
