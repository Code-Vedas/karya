# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'json'
require 'securerandom'
require 'tmpdir'

# Shared helpers for framework-host E2E workflow and delayed scheduling checks.
module FrameworkE2ESupport
  REDIS_DELAYED_JOB_PRECISION = 0

  def current_app_root
    Thread.current[:karya_current_app_root]
  end

  def current_app_root=(path)
    Thread.current[:karya_current_app_root] = path
  end

  def framework_root_path_for_e2e
    current_app_root || described_class.framework_root_path
  end

  def framework_job_base_for_e2e
    described_class.const_get(:Job)
  end

  def framework_workflow_for_e2e
    described_class.const_get(:Workflow)
  end

  def reset_framework_workflow_facade!
    framework_workflow_for_e2e.instance_variable_set(:@facade, nil)
  end

  def run_framework_worker_for_e2e(queue:, handlers:, max_iterations:)
    if [Karya::Backend::InMemory, Karya::Backend::SQLite].include?(Karya.backend_class)
      Karya::Worker.new(
        queue_store: framework_worker_queue_store,
        queues: [queue],
        handlers:,
        worker_id: "#{described_class.name.split('::').last.downcase}-e2e-worker",
        lease_duration: 60
      ).run(
        poll_interval: 0,
        stop_when_idle: true,
        max_iterations:
      )
    else
      described_class.support.run_worker(
        queues: [queue],
        root_path: framework_root_path_for_e2e,
        extra_handlers: handlers,
        threads: 1,
        processes: 1,
        lease_duration: 60,
        poll_interval: 0,
        stop_when_idle: true,
        max_iterations:
      )
    end
  end

  def framework_worker_queue_store
    return Karya.queue_store if Karya.backend_class == Karya::Backend::InMemory

    Karya._resolve_queue_store
  end

  def workflow_marker_entries(marker_path)
    JSON.parse(File.read(marker_path))
  end

  def delayed_job_payloads
    Kaal.configuration.backend.delayed_store.all_jobs
  end

  def decode_delayed_enqueue_request(job_payload)
    Karya::Internal::DelayedEnqueueJob.deserialize_request(job_payload.fetch(:args).first)
  end

  def expected_delayed_run_at(scheduled_at)
    return scheduled_at unless Karya.backend_class == Karya::Backend::Redis

    Time.iso8601(scheduled_at.iso8601(REDIS_DELAYED_JOB_PRECISION))
  end

  def with_bound_queue_store
    snapshot = Karya::Internal::QueueStoreBinding.capture
    Karya.configure_queue_store(Karya._resolve_queue_store)
    yield
  ensure
    Karya::Internal::QueueStoreBinding.restore(snapshot)
  end
end

RSpec.configure do |config|
  config.include FrameworkE2ESupport
end

RSpec.shared_examples 'framework workflow worker e2e' do |backend_identifier:|
  it 'executes a framework-native workflow through the worker runtime' do
    with_bound_queue_store do
      reset_framework_workflow_facade!

      Dir.mktmpdir("#{described_class.name.split('::').last.downcase}-workflow-e2e-") do |directory|
        marker_path = File.join(directory, 'workflow-events.json')
        queue_name = "#{backend_identifier}_workflow_e2e"
        handler_prefix = "#{described_class.name.split('::').last.downcase}_#{backend_identifier}_workflow"
        batch_id = "#{handler_prefix}_#{SecureRandom.hex(6)}"

        prepare_job = Class.new(framework_job_base_for_e2e) do
          queue_as queue_name
          karya_handler "#{handler_prefix}_prepare"

          define_method(:perform) do |marker_path:, account_id:|
            entries = File.exist?(marker_path) ? JSON.parse(File.read(marker_path)) : []
            entries << { 'step' => 'prepare', 'account_id' => account_id }
            File.write(marker_path, JSON.generate(entries))
          end
        end

        settle_job = Class.new(framework_job_base_for_e2e) do
          queue_as queue_name
          karya_handler "#{handler_prefix}_settle"

          define_method(:perform) do |marker_path:, account_id:|
            entries = File.exist?(marker_path) ? JSON.parse(File.read(marker_path)) : []
            entries << { 'step' => 'settle', 'account_id' => account_id }
            File.write(marker_path, JSON.generate(entries))
          end
        end

        definition = framework_workflow_for_e2e.define(
          "#{handler_prefix}_definition",
          workflow_family: "#{handler_prefix}_family",
          workflow_version: 'v1',
          default_version: true
        ) do |workflow|
          workflow.step(:prepare, job: prepare_job, arguments: prepare_job.arguments(marker_path:, account_id: 42))
          workflow.step(:settle, job: settle_job, depends_on: :prepare, arguments: settle_job.arguments(marker_path:, account_id: 42))
        end

        framework_workflow_for_e2e.start(
          definition:,
          batch_id:,
          step_arguments: {},
          now: Time.now.utc
        )

        run_framework_worker_for_e2e(
          queue: queue_name,
          handlers: {
            prepare_job.handler_name => prepare_job,
            settle_job.handler_name => settle_job
          },
          max_iterations: 2
        )

        snapshot = Karya.queue_store.workflow_snapshot(batch_id:, now: Time.now.utc + 60)

        expect(snapshot).to have_attributes(state: :succeeded)
        expect(snapshot.fetch_step(:prepare)).to have_attributes(state: :succeeded)
        expect(snapshot.fetch_step(:settle)).to have_attributes(state: :succeeded)
        expect(workflow_marker_entries(marker_path)).to eq(
          [
            { 'step' => 'prepare', 'account_id' => 42 },
            { 'step' => 'settle', 'account_id' => 42 }
          ]
        )
      end
    end
  end
end

RSpec.shared_examples 'framework delayed scheduling e2e' do |backend_identifier:|
  it 'round-trips a delayed enqueue through Kaal and the framework worker runtime' do
    Dir.mktmpdir("#{described_class.name.split('::').last.downcase}-delayed-e2e-") do |directory|
      marker_path = File.join(directory, 'delayed-job.json')
      queue_name = "#{backend_identifier}_delayed_e2e"
      handler_name = "#{described_class.name.split('::').last.downcase}_#{backend_identifier}_delayed_handler"
      job_id = "#{handler_name}_#{SecureRandom.hex(6)}"
      scheduled_at = Time.now.utc + 0.3
      now = Time.now.utc

      delayed_job = Class.new(framework_job_base_for_e2e) do
        queue_as queue_name
        karya_handler handler_name

        define_method(:perform) do |marker_path:, payload:, scheduled_at:|
          File.write(
            marker_path,
            JSON.generate(
              'payload' => payload,
              'scheduled_at' => scheduled_at,
              'handler' => self.class.handler_name,
              'queue' => self.class.queue_name
            )
          )
        end
      end

      framework_arguments = delayed_job.arguments(
        marker_path:,
        payload: 'scheduled delivery',
        scheduled_at: scheduled_at.iso8601(6)
      ).to_payload

      receipt = Karya.enqueue_at(
        queue: queue_name,
        handler: delayed_job.handler_name,
        arguments: framework_arguments,
        at: scheduled_at,
        now: now,
        job_id:
      )

      delayed_payload = delayed_job_payloads.fetch(0)
      request_payload = decode_delayed_enqueue_request(delayed_payload)
      expected_run_at = expected_delayed_run_at(scheduled_at)

      expect(receipt).to include(
        job_id: job_id,
        run_at: expected_run_at,
        job_class: 'Karya::Internal::DelayedEnqueueJob',
        queue: nil
      )
      expect(request_payload).to include(
        'queue' => queue_name,
        'handler' => delayed_job.handler_name,
        'job_id' => job_id
      )
      expect(request_payload.fetch('arguments')).to eq(framework_arguments)

      sleep([scheduled_at - Time.now.utc + 0.1, 0].max)
      wait_until(timeout: 5) do
        Kaal.tick!
        delayed_job_payloads.empty?
      end

      run_framework_worker_for_e2e(
        queue: queue_name,
        handlers: { delayed_job.handler_name => delayed_job },
        max_iterations: 3
      )

      expect(JSON.parse(File.read(marker_path))).to include(
        'payload' => 'scheduled delivery',
        'scheduled_at' => scheduled_at.iso8601(6),
        'handler' => delayed_job.handler_name,
        'queue' => queue_name
      )
      expect(delayed_job_payloads).to eq([])
    end
  end
end
