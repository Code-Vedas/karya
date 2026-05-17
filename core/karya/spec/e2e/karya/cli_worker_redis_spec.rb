# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Karya::CLI, :e2e, :integration do
  def delete_redis_namespace(redis_url:, namespace:)
    client = Redis.new(url: redis_url)
    keys = client.scan_each(match: "#{namespace}:queue_store:*").to_a
    client.del(*keys) unless keys.empty?
  end

  def redis_boot_file(redis_url:, namespace:, marker_file:)
    <<~RUBY
      # frozen_string_literal: true

      now = Time.utc(2026, 5, 5, 12, 0, 0)
      queue_store = Karya::Backend::Redis.new(
        url: #{redis_url.inspect},
        namespace: #{namespace.inspect}
      ).build_queue_store
      queue_store.enqueue(
        job: Karya::Job.new(
          id: 'job-redis-1',
          queue: 'billing',
          handler: 'billing_sync',
          arguments: { 'account_id' => 42, 'marker_path' => #{marker_file.inspect} },
          state: :submission,
          created_at: now
        ),
        now: now
      )
      Karya.configure_backend(Karya::Backend::Redis, url: #{redis_url.inspect}, namespace: #{namespace.inspect})

      class CliWorkerRedisHandler
        def self.call(account_id:, marker_path:)
          File.write(marker_path, JSON.generate('account_id' => account_id, 'pid' => Process.pid))
        end
      end
    RUBY
  end

  it 'boots a worker through the Redis backend path when an external Redis server is configured' do
    redis_url = ENV.fetch('KARYA_REDIS_URL', nil)
    skip 'set KARYA_REDIS_URL for Redis e2e coverage' unless redis_url

    Dir.mktmpdir('karya-cli-redis-e2e') do |directory|
      state_file = File.join(directory, 'runtime.json')
      marker_file = File.join(directory, 'handler.json')
      namespace = "karya-redis-e2e-#{Process.pid}-#{File.basename(directory)}"
      boot_file = File.join(directory, 'worker_boot.rb')

      File.write(boot_file, redis_boot_file(redis_url:, namespace:, marker_file:))

      stdout, stderr, status = Open3.capture3(
        *karya_command(
          'worker',
          'billing',
          '--require',
          boot_file,
          '--handler',
          'billing_sync=CliWorkerRedisHandler',
          '--worker-id',
          'worker-cli-redis-e2e',
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
    ensure
      delete_redis_namespace(redis_url:, namespace:)
    end
  end
end
