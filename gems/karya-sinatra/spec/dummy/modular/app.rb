# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'sinatra/base'
require 'karya/sinatra'
require 'securerandom'

class KaryaSinatraDummyApp < Sinatra::Base
  set :root, File.expand_path(__dir__)
  disable :protection

  get '/karya' do
    content_type 'text/html'
    Karya::Sinatra.render_dashboard_page
  end

  get '/karya/runtime-probe' do
    queue_store = Karya.backend_class.new(**Karya.backend_options).build_queue_store
    now = Time.now.utc
    job = Karya::Job.new(
      id: "sinatra-modular-probe-#{SecureRandom.uuid}",
      queue: 'dashboard',
      handler: 'dashboard_probe',
      state: :submission,
      created_at: now
    )
    queue_store.enqueue(job:, now:)
    reservation = queue_store.reserve(queue: 'dashboard', worker_id: 'sinatra-modular-probe-worker', lease_duration: 60, now: now + 1)
    content_type 'application/json'
    %({"backend":"#{Karya.backend_class.new(**Karya.backend_options).identifier}","job_id":"#{reservation.job_id}"})
  end
end
