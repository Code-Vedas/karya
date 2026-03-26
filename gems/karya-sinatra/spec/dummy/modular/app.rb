# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'sinatra/base'
require 'karya/sinatra'

class KaryaSinatraDummyApp < Sinatra::Base
  set :root, File.expand_path(__dir__)

  get '/karya' do
    content_type 'text/html'
    Karya::Sinatra.render_dashboard_page(scope: 'ops')
  end
end
