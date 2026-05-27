# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::FrameworkJobRegistry do
  around do |example|
    original_entries = []
    original_entries = described_class.entries
    described_class.reset!
    example.run
  ensure
    described_class.reset!
    original_entries.each do |entry|
      described_class.register(entry.klass, source_path: entry.source_path)
    end
  end

  it 'returns a stable snapshot of registered entries' do
    first_job = Class.new(Karya::FrameworkJob::Base)
    described_class.register(first_job, source_path: '/tmp/first_job.rb')
    snapshot = described_class.entries
    second_job = Class.new(Karya::FrameworkJob::Base)
    described_class.register(second_job, source_path: '/tmp/second_job.rb')

    expect(snapshot.map(&:klass)).to contain_exactly(first_job)
    expect(described_class.entries.map(&:klass)).to contain_exactly(first_job, second_job)
  end

  it 'returns an array snapshot that callers can mutate without affecting the registry' do
    job_class = Class.new(Karya::FrameworkJob::Base)
    described_class.register(job_class, source_path: '/tmp/registered_job.rb')

    snapshot = described_class.entries
    snapshot.clear

    expect(described_class.entries.map(&:klass)).to contain_exactly(job_class)
  end

  it 'preserves a nil source path' do
    job_class = Class.new(Karya::FrameworkJob::Base)

    described_class.register(job_class, source_path: nil)

    expect(described_class.entries.fetch(0).source_path).to be_nil
  end

  it 'supports concurrent registration and reads' do
    start_queue = Queue.new
    registered_jobs = Queue.new
    reader_results = Queue.new

    writer_threads = Array.new(8) do |index|
      Thread.new do
        start_queue.pop
        job_class = Class.new(Karya::FrameworkJob::Base)
        described_class.register(job_class, source_path: "/tmp/job_#{index}.rb")
        registered_jobs << job_class
      end
    end

    reader_threads = Array.new(4) do
      Thread.new do
        start_queue.pop
        reader_results << described_class.entries
      end
    end

    (writer_threads.length + reader_threads.length).times { start_queue << true }
    (writer_threads + reader_threads).each(&:join)

    final_entries = described_class.entries
    registered_classes = Array.new(writer_threads.length) { registered_jobs.pop }
    observed_reader_results = Array.new(reader_threads.length) { reader_results.pop }

    expect(final_entries.map(&:klass)).to match_array(registered_classes)
    expect(observed_reader_results).to all(be_an(Array))
  end
end
