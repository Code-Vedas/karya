# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'roda'
require 'karya/roda'

class KaryaRodaDummyApp < Roda
  route do |r|
    r.is 'karya' do
      response['content-type'] = 'text/html; charset=utf-8'
      Karya::Roda.render_dashboard_page(scope: 'internal')
    end
  end
end
