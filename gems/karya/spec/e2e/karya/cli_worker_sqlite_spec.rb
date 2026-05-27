# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../spec_helper'
require File.expand_path('../../../../../spec/support/sqlite_e2e_support', __dir__)

RSpec.describe Karya::CLI, :e2e, :integration do
  def sqlite_boot_file(sqlite_url:, namespace:, marker_file:)
    <<~RUBY
      # frozen_string_literal: true

      now = Time.utc(2026, 5, 5, 12, 0, 0)
      queue_store = Karya::Backend::SQLite.new(
        url: #{sqlite_url.inspect},
        namespace: #{namespace.inspect}
      ).build_queue_store
      queue_store.enqueue(
        job: Karya::Job.new(
          id: 'job-sqlite-1',
          queue: 'billing',
          handler: 'billing_sync',
          arguments: { 'account_id' => 42, 'marker_path' => #{marker_file.inspect} },
          state: :submission,
          created_at: now
        ),
        now: now
      )
      queue_store.connection.close
      Karya.configure_backend(Karya::Backend::SQLite, url: #{sqlite_url.inspect}, namespace: #{namespace.inspect})

      class CliWorkerSQLiteHandler
        def self.call(account_id:, marker_path:)
          File.write(marker_path, JSON.generate('account_id' => account_id, 'pid' => Process.pid))
        end
      end
    RUBY
  end

  it 'boots a worker through the SQLite backend path with a local durable database file' do
    with_sqlite_database(prefix: 'karya_cli_sqlite_e2e') do |database_url|
      Dir.mktmpdir('karya-cli-sqlite-e2e') do |directory|
        state_file = File.join(directory, 'runtime.json')
        marker_file = File.join(directory, 'handler.json')
        namespace = "karya-sqlite-e2e-#{Process.pid}-#{File.basename(directory)}"
        boot_file = File.join(directory, 'worker_boot.rb')

        File.write(boot_file, sqlite_boot_file(sqlite_url: database_url, namespace:, marker_file:))

        stdout, stderr, status = Open3.capture3(
          *karya_command(
            'worker',
            'billing',
            '--require',
            boot_file,
            '--handler',
            'billing_sync=CliWorkerSQLiteHandler',
            '--worker-id',
            'worker-cli-sqlite-e2e',
            '--processes',
            '1',
            '--threads',
            '1',
            '--poll-interval',
            '0',
            '--max-iterations',
            '1',
            '--state-file',
            state_file
          ),
          chdir: KaryaE2EHelpers::PACKAGE_ROOT
        )

        expect(status.exitstatus).to eq(0), -> { "stdout:\n#{stdout}\n\nstderr:\n#{stderr}" }
        expect(JSON.parse(File.read(marker_file))).to include('account_id' => 42)
        expect(read_runtime_state(state_file).fetch('snapshot').fetch('phase')).to eq('stopped')
      end
    end
  end
end
