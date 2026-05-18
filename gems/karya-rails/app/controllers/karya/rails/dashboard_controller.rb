# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'

module Karya
  module Rails
    # Serves the packaged dashboard document and a lightweight runtime probe.
    class DashboardController < ApplicationController
      # Executes a minimal queue-store round-trip against the configured backend.
      class RuntimeProbe
        def initialize(backend:, now:)
          @backend = backend
          @now = now
        end

        def call
          queue_store.enqueue(job: probe_job, now:)
          queue_store.reserve(queue: 'dashboard', worker_id: 'rails-probe-worker', lease_duration: 60, now: now + 1)
        end

        private

        attr_reader :backend, :now

        def queue_store
          @queue_store ||= backend.build_queue_store
        end

        def probe_job
          Karya::Job.new(
            id: "rails-probe-#{SecureRandom.uuid}",
            queue: 'dashboard',
            handler: 'dashboard_probe',
            state: :submission,
            created_at: now
          )
        end
      end

      def show
        render body: Karya::Rails.render_dashboard_page(
          mount_path: request.script_name.presence || Karya::Rails::DEFAULT_MOUNT_PATH
        ), content_type: 'text/html'
      end

      def runtime_probe
        render json: runtime_probe_payload
      end

      private

      def runtime_probe_payload
        backend = Karya.backend_class.new(**Karya.backend_options)
        now = Time.now.utc
        reservation = RuntimeProbe.new(backend:, now:).call

        {
          backend: backend.identifier,
          job_id: reservation.job_id,
          mount_path: request.script_name.presence || Karya::Rails::DEFAULT_MOUNT_PATH
        }
      end
    end
  end
end
