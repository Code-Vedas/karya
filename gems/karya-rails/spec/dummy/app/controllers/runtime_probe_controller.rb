# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'

class RuntimeProbeController < ApplicationController
  def show
    render json: Karya::Rails.runtime_probe_payload
  end

  def kaal
    runtime_context = Kaal::Runtime::RuntimeContext.new(
      root_path: Rails.root,
      environment_name: Rails.env
    )
    Kaal.load_scheduler_file!(runtime_context:)
    render json: {
      'backend' => Kaal.configuration.backend.class.name,
      'registered' => Kaal.registered?(key: 'rails:heartbeat')
    }
  end

  def active_job
    Karya::RailsDummyJob.queue_adapter = Karya::Rails.active_job_queue_adapter
    Karya::RailsDummyJob.perform_later('hello from active job')
    render json: { 'adapter' => Karya::Rails.active_job_queue_adapter.class.name }
  end
end
