# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../rails_helper'

RSpec.describe 'Karya::Rails engine requests', :dashboard_manifest_fixture, type: :request do
  around do |example|
    original_authorizer = Karya::Rails.operator_authorizer
    example.run
  ensure
    Karya::Rails.configure_operator_authorizer(original_authorizer)
  end

  it 'serves the dashboard and runtime endpoints when authorized' do
    Karya::Rails.configure_operator_authorizer(->(_request_context) { true })
    allow(Karya::Rails).to receive_messages(
      health_payload: { 'status' => 'ok' },
      readiness_payload: { 'status' => 'ready' },
      operator_payload: { 'status' => 'operator' }
    )

    get '/karya'
    expect(response).to have_http_status(:ok)

    get '/karya/health'
    expect(response).to have_http_status(:ok)

    get '/karya/readiness'
    expect(response).to have_http_status(:ok)

    get '/karya/operator'
    expect(response).to have_http_status(:ok)
  end

  it 'rejects operator-protected endpoints when unauthorized' do
    Karya::Rails.configure_operator_authorizer(->(_request_context) { false })

    get '/karya'
    expect(response).to have_http_status(:forbidden)

    get '/karya/operator'
    expect(response).to have_http_status(:forbidden)
  end
end
