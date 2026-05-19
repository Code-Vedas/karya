# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'roda'
require 'karya/roda'
require 'securerandom'

class KaryaRodaDummyApp < Roda
  route do |r|
    r.is 'karya', 'runtime-probe' do
      backend = Karya.backend_class.new(**Karya.backend_options)
      queue_store = backend.build_queue_store
      now = Time.now.utc
      job = Karya::Job.new(
        id: "roda-probe-#{SecureRandom.uuid}",
        queue: 'dashboard',
        handler: 'dashboard_probe',
        state: :submission,
        created_at: now
      )
      queue_store.enqueue(job:, now:)
      reservation = queue_store.reserve(queue: 'dashboard', worker_id: 'roda-probe-worker', lease_duration: 60, now: now + 1)
      response['content-type'] = 'application/json; charset=utf-8'
      %({"backend":"#{backend.identifier}","job_id":"#{reservation.job_id}"})
    end

    r.is 'karya' do
      response['content-type'] = 'text/html; charset=utf-8'
      Karya::Roda.render_dashboard_page
    end
  end
end
