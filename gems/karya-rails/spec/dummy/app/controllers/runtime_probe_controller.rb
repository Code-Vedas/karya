# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'

class RuntimeProbeController < ApplicationController
  def show
    backend = Karya.backend_class.new(**Karya.backend_options)
    queue_store = backend.build_queue_store
    now = Time.now.utc
    job = Karya::Job.new(
      id: "rails-probe-#{SecureRandom.uuid}",
      queue: 'dashboard',
      handler: 'dashboard_probe',
      state: :submission,
      created_at: now
    )
    queue_store.enqueue(job:, now:)
    reservation = queue_store.reserve(queue: 'dashboard', worker_id: 'rails-probe-worker', lease_duration: 60, now: now + 1)

    render json: {
      backend: backend.identifier,
      job_id: reservation.job_id,
      mount_path: '/karya'
    }
  end
end
