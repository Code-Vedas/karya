# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
KaryaRailsDummy::Application.routes.draw do
  get 'up' => 'rails/health#show', as: :rails_health_check
  get '/karya/runtime-probe', to: 'runtime_probe#show'
  get '/kaal/probe', to: 'runtime_probe#kaal'
  get '/karya/active-job-probe', to: 'runtime_probe#active_job'
  mount Karya::Rails::Engine => '/karya'
end
