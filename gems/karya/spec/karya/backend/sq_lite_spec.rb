# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'open3'
require 'rbconfig'
require 'tmpdir'

RSpec.describe Karya::Backend::SQLite do
  def sqlite_url_for(directory)
    "sqlite3:///#{File.join(directory, 'karya.sqlite3').sub(%r{\A/+}, '')}"
  end

  def standalone_queue_store_script
    <<~RUBY
      require 'tmpdir'
      require 'karya/queue_store/sqlite'

      Dir.mktmpdir('karya-standalone-sqlite-') do |directory|
        url = "sqlite3:///" + File.join(directory, 'karya.sqlite3').sub(%r{\A/+}, '')
        now = Time.utc(2026, 5, 5, 12, 0, 0)
        store = Karya::QueueStore::SQLite.new(url:, namespace: 'standalone')
        job = Karya::Job.new(id: 'job-1', queue: 'billing', handler: 'billing_sync', state: :submission, created_at: now)
        store.enqueue(job:, now: now + 1)
        reservation = store.reserve(queue: 'billing', worker_id: 'worker-1', lease_duration: 60, now: now + 2)
        store.start_execution(reservation_token: reservation.token, now: now + 3)
        failed = store.fail_execution(reservation_token: reservation.token, now: now + 4, failure_classification: :error)
        puts failed.state
      end
    RUBY
  end

  it 'loads as a standalone backend file' do
    lib_path = File.expand_path('../../../lib', __dir__)
    script = <<~RUBY
      require 'karya/backend/sqlite'
      puts Karya::Backend::SQLite.new(url: 'sqlite3:///tmp/karya.sqlite3').identifier
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status.success?).to be(true), stderr
    expect(stdout).to eq("sqlite\n")
  end

  it 'loads SQLite queue-store execution paths as a standalone file' do
    lib_path = File.expand_path('../../../lib', __dir__)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', standalone_queue_store_script)

    expect(status.success?).to be(true), stderr
    expect(stdout).to eq("failed\n")
  end

  it 'raises an actionable load error when the sqlite3 gem is not available' do
    lib_path = File.expand_path('../../../lib', __dir__)
    script = <<~RUBY
      module Kernel
        alias_method :__karya_original_require_for_sqlite_spec, :require

        def require(name)
          raise LoadError, 'cannot load such file -- sqlite3' if name == 'sqlite3'

          __karya_original_require_for_sqlite_spec(name)
        end
      end

      begin
        require 'karya/backend/sqlite'
        Karya::Backend::SQLite.new(url: 'sqlite3:///tmp/karya.sqlite3').build_queue_store
      rescue LoadError => e
        warn e.message
        exit 0
      end

      exit 1
    RUBY

    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_path, '-e', script)

    expect(status.success?).to be(true)
    expect(stderr).to include("Add `gem 'sqlite3'` to your Gemfile to use Karya::Backend::SQLite and Karya::QueueStore::SQLite.")
  end

  it 'raises an actionable load error from the dependency loader when sqlite3 is unavailable' do
    dependency_loader = Karya::QueueStore::SQLite.send(:const_get, :Internal).const_get(:DependencyLoader)
    allow(dependency_loader).to receive(:require).with('sqlite3').and_raise(LoadError, 'cannot load such file -- sqlite3')

    expect do
      dependency_loader.require_sqlite3!
    end.to raise_error(
      LoadError,
      /Add `gem 'sqlite3'` to your Gemfile to use Karya::Backend::SQLite and Karya::QueueStore::SQLite\./
    )
  end

  it 'exposes the backend identifier' do
    backend = described_class.new(url: 'sqlite3:///tmp/karya.sqlite3')

    expect(backend.identifier).to eq('sqlite')
  end

  it 'builds the SQLite queue store owned by the backend definition' do
    Dir.mktmpdir('karya-sqlite-backend-build-') do |directory|
      queue_store = described_class.new(url: sqlite_url_for(directory)).build_queue_store

      expect(queue_store).to be_a(Karya::QueueStore::SQLite)
    end
  end

  it 'forwards namespace and queue-store options to the queue store' do
    Dir.mktmpdir('karya-sqlite-backend-options-') do |directory|
      queue_store = described_class.new(
        url: sqlite_url_for(directory),
        namespace: 'payments',
        max_batch_size: 50
      ).build_queue_store

      expect(queue_store.send(:namespace)).to eq('payments')
      expect(queue_store.send(:max_batch_size)).to eq(50)
    end
  end

  it 'normalizes invalid queue-store keyword errors into backend configuration errors' do
    Dir.mktmpdir('karya-sqlite-backend-invalid-keywords-') do |directory|
      invalid_backend = described_class.new(
        url: sqlite_url_for(directory),
        namespace: 'payments',
        unsupported_option: true
      )

      expect do
        invalid_backend.build_queue_store
      end.to raise_error(
        Karya::InvalidBackendConfigurationError,
        /invalid SQLite backend queue-store configuration: unexpected option keys :unsupported_option: unknown keywords: unsupported_option/
      ) { |error| expect(error.cause).to be_a(ArgumentError) }
    end
  end

  it 'normalizes queue-store validation failures into backend configuration errors' do
    invalid_backend = described_class.new(url: ' ', namespace: 'payments')

    expect do
      invalid_backend.build_queue_store
    end.to raise_error(
      Karya::InvalidBackendConfigurationError,
      /invalid SQLite backend queue-store configuration: url must be a non-empty String/
    ) { |error| expect(error.cause).to be_a(Karya::InvalidQueueStoreOperationError) }
  end
end
