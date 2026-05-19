# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'hanami'
require 'karya/hanami'
require 'securerandom'

KaryaHanamiDummyApp = proc do |env|
  if env['PATH_INFO'] == '/karya/runtime-probe'
    backend = Karya.backend_class.new(**Karya.backend_options)
    queue_store = backend.build_queue_store
    now = Time.now.utc
    job = Karya::Job.new(
      id: "hanami-probe-#{SecureRandom.uuid}",
      queue: 'dashboard',
      handler: 'dashboard_probe',
      state: :submission,
      created_at: now
    )
    queue_store.enqueue(job:, now:)
    reservation = queue_store.reserve(queue: 'dashboard', worker_id: 'hanami-probe-worker', lease_duration: 60, now: now + 1)
    [
      200,
      { 'content-type' => 'application/json; charset=utf-8' },
      [%({"backend":"#{backend.identifier}","job_id":"#{reservation.job_id}"})]
    ]
  elsif env['PATH_INFO'] == '/karya'
    [
      200,
      { 'content-type' => 'text/html; charset=utf-8' },
      [Karya::Hanami.render_dashboard_page]
    ]
  else
    [404, { 'content-type' => 'text/plain' }, ['not found']]
  end
end
