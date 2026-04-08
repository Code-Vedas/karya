# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require_relative '../spec_helper'
require 'json'
require 'open3'
require 'rbconfig'
require 'timeout'
require 'tmpdir'
require 'fileutils'

module KaryaE2EHelpers
  PACKAGE_ROOT = File.expand_path('../..', __dir__)

  def karya_command(*args)
    ['bundle', 'exec', RbConfig.ruby, '-Ilib', 'exe/karya', *args]
  end

  def write_boot_file(directory:, handler_class_name:, handler_body:, marker_path: nil, queue: 'billing', job_id: 'job-1')
    handler_file = File.join(directory, 'worker_boot.rb')
    marker_literal = marker_path&.inspect || 'nil'
    File.write(
      handler_file,
      <<~RUBY
        # frozen_string_literal: true

        now = Time.utc(2026, 4, 7, 12, 0, 0)
        queue_store = Karya::QueueStore::InMemory.new(token_generator: -> { 'lease-token' })
        Karya.configure_queue_store(queue_store)
        queue_store.enqueue(
          job: Karya::Job.new(
            id: #{job_id.inspect},
            queue: #{queue.inspect},
            handler: 'billing_sync',
            arguments: { 'account_id' => 42, 'marker_path' => #{marker_literal} },
            state: :submission,
            created_at: now
          ),
          now: now
        )

        class #{handler_class_name}
          def self.call(account_id:, marker_path: nil)
            #{handler_body}
          end
        end
      RUBY
    )
    handler_file
  end

  def read_runtime_state(state_file)
    JSON.parse(File.read(state_file))
  end

  def wait_until(timeout: 10)
    Timeout.timeout(timeout) do
      loop do
        result = yield
        return result if result

        sleep(0.05)
      end
    end
  end
end

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.include KaryaE2EHelpers
end
