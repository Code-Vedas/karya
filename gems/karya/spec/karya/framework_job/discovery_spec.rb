# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'fileutils'

RSpec.describe Karya::FrameworkJob::Discovery do
  around do |example|
    original_entries = []
    begin
      original_entries = Karya::Internal::FrameworkJobRegistry.entries.dup
      Karya::Internal::FrameworkJobRegistry.reset!
      example.run
    ensure
      Karya::Internal::FrameworkJobRegistry.reset!
      original_entries.each do |entry|
        Karya::Internal::FrameworkJobRegistry.register(
          entry.klass,
          source_path: entry.source_path
        )
      end
    end
  end

  it 'discovers framework jobs from the target app root only' do
    Dir.mktmpdir('karya-framework-job-discovery-') do |root|
      jobs_dir = File.join(root, 'app/jobs')
      FileUtils.mkdir_p(jobs_dir)
      File.write(
        File.join(jobs_dir, 'billing_sync_job.rb'),
        <<~RUBY
          class DiscoveryApplicationJob < Karya::FrameworkJob::Base
            abstract!
          end

          class BillingSyncJob < DiscoveryApplicationJob
            queue_as :billing

            def perform(account_id)
              account_id
            end
          end
        RUBY
      )

      handlers = described_class.new(
        root_path: root,
        job_base: Karya::FrameworkJob::Base
      ).handlers

      expect(handlers.keys).to include('BillingSyncJob')
      expect(handlers).not_to include('Karya::FrameworkJobBaseSpecJob')
    end
  end

  it 'loads boot files and merges extra handlers' do
    Dir.mktmpdir('karya-framework-job-discovery-boot-') do |root|
      FileUtils.mkdir_p(File.join(root, 'config/boot'))
      FileUtils.mkdir_p(File.join(root, 'app/jobs'))
      File.write(File.join(root, 'config/boot/jobs.rb'), "module DiscoveryBootFlag\n  VALUE = 'loaded'\nend\n")
      File.write(
        File.join(root, 'app/jobs', 'booted_job.rb'),
        <<~RUBY
          class BootedJob < Karya::FrameworkJob::Base
            def perform = nil
          end
        RUBY
      )

      handlers = described_class.new(
        root_path: root,
        job_base: Karya::FrameworkJob::Base,
        boot_files: ['config/boot/jobs.rb'],
        extra_handlers: { 'active_job' => Object.new }
      ).handlers

      expect(handlers.keys).to include('BootedJob', 'active_job')
      expect(DiscoveryBootFlag::VALUE).to eq('loaded')
      hide_const('DiscoveryBootFlag')
    end
  end

  it 'rejects invalid discovery configuration' do
    expect do
      described_class.new(root_path: Dir.pwd, job_base: Karya::FrameworkJob::Base, job_paths: 'app/jobs')
    end.to raise_error(ArgumentError, /job_paths must be an Array/)

    expect do
      described_class.new(root_path: Dir.pwd, job_base: Karya::FrameworkJob::Base, extra_handlers: [])
    end.to raise_error(ArgumentError, /extra_handlers must be a Hash/)

    expect do
      described_class.new(root_path: Dir.pwd, job_base: Karya::FrameworkJob::Base, boot_files: [Object.new])
    end.to raise_error(ArgumentError, /boot_files entries must be Strings/)
  end

  it 'ignores classes outside configured job paths even when they inherit from the framework base' do
    Dir.mktmpdir('karya-framework-job-discovery-outside-jobs-') do |root|
      outside_job = Class.new(Karya::FrameworkJob::Base) do
        def self.name = 'DiscoveryOutsideJob'
        def perform = nil
      end
      Karya::Internal::FrameworkJobRegistry.register(outside_job, source_path: File.join(root, 'lib/discovery_outside_job.rb'))

      handlers = described_class.new(root_path: root, job_base: Karya::FrameworkJob::Base).handlers

      expect(handlers.keys).not_to include('DiscoveryOutsideJob')
    end
  end

  it 'discovers classes defined in app jobs even when perform comes from a shared module' do
    Dir.mktmpdir('karya-framework-job-discovery-shared-perform-') do |root|
      FileUtils.mkdir_p(File.join(root, 'app/jobs'))
      FileUtils.mkdir_p(File.join(root, 'lib'))
      File.write(
        File.join(root, 'lib/shared_perform.rb'),
        <<~RUBY
          module DiscoverySharedPerform
            def perform
              :ok
            end
          end
        RUBY
      )
      File.write(
        File.join(root, 'app/jobs/shared_perform_job.rb'),
        <<~RUBY
          require_relative '../../lib/shared_perform'

          class SharedPerformJob < Karya::FrameworkJob::Base
            include DiscoverySharedPerform
          end
        RUBY
      )

      handlers = described_class.new(root_path: root, job_base: Karya::FrameworkJob::Base).handlers

      expect(handlers.keys).to include('SharedPerformJob')
    end
  end

  it 'supports missing eager-load hooks and rejects blank paths' do
    discovery = described_class.new(root_path: Dir.pwd, job_base: Karya::FrameworkJob::Base, boot_files: [''])
    expect(discovery.send(:boot_files)).to eq([])

    Dir.mktmpdir('karya-framework-job-discovery-eager-load-') do |root|
      FileUtils.mkdir_p(File.join(root, 'app/jobs'))
      File.write(
        File.join(root, 'app/jobs', 'eager_job.rb'),
        <<~RUBY
          class DiscoveryEagerJob < Karya::FrameworkJob::Base
            def perform
            end
          end
        RUBY
      )

      nil_eager_load_discovery = described_class.new(root_path: root, job_base: Karya::FrameworkJob::Base, eager_load: nil)
      expect(nil_eager_load_discovery.handlers.keys).to include('DiscoveryEagerJob')
    end
  end

  it 'covers eager-load and ancestry edge cases through private helpers' do
    eager_load_calls = 0
    discovery = described_class.new(
      root_path: Dir.pwd,
      job_base: Karya::FrameworkJob::Base,
      eager_load: -> { eager_load_calls += 1 }
    )

    allow(discovery).to receive(:job_files).and_return([])
    discovery.send(:load_environment)
    expect(eager_load_calls).to eq(1)
    expect(discovery.send(:defined_under_job_paths?, nil)).to be(false)

    hostile_class = Class.new do
      def self.<(_other)
        raise NoMethodError, 'hostile class'
      end
    end
    hostile_entry = Karya::Internal::FrameworkJobRegistry::Entry.new(klass: hostile_class, source_path: __FILE__)
    expect(hostile_entry.framework_job_class?(Karya::FrameworkJob::Base)).to be(false)
  end
end
