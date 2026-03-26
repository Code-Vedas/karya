# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
KaryaRailsDummy::Application.routes.draw do
  get 'up' => 'rails/health#show', as: :rails_health_check
  mount Karya::Rails::Engine => '/karya'
end
