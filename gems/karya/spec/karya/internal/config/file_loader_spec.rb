# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Internal::Config::FileLoader do
  subject(:loader) { described_class.new(configuration:, runtime_context:) }

  let(:configuration) { Karya::Internal::FrameworkConfiguration.new }
  let(:root) { Dir.mktmpdir('karya-config-loader-') }
  let(:runtime_context) do
    Karya::Internal::Config::RuntimeContext.new(root_path: root, environment_name: 'test')
  end

  around do |example|
    original_backend_class = Karya.instance_variable_get(:@backend_class) if Karya.instance_variable_defined?(:@backend_class)
    original_backend_options = Karya.instance_variable_get(:@backend_options) if Karya.instance_variable_defined?(:@backend_options)
    RSpec::Mocks.with_temporary_scope do
      allow(Karya).to receive(:synchronize_kaal_backend)
      example.run
    end
  ensure
    if defined?(original_backend_class)
      Karya.instance_variable_set(:@backend_class, original_backend_class)
    elsif Karya.instance_variable_defined?(:@backend_class)
      Karya.remove_instance_variable(:@backend_class)
    end

    if defined?(original_backend_options)
      Karya.instance_variable_set(:@backend_options, original_backend_options)
    elsif Karya.instance_variable_defined?(:@backend_options)
      Karya.remove_instance_variable(:@backend_options)
    end
  end

  after do
    FileUtils.remove_entry(root)
  end

  it 'loads defaults merged with the current environment' do
    File.write(
      File.join(root, 'karya.yml'),
      <<~YAML
        defaults:
          backend: sqlite
          backend_config:
            url: sqlite3:///tmp/default.sqlite3
          job_paths:
            - app/jobs
          boot_files: []

        test:
          backend: postgres
          backend_config:
            url: postgres://localhost/test
          job_paths:
            - app/jobs
            - lib/jobs
          boot_files:
            - config/boot/jobs.rb
      YAML
    )

    loader.load(path: 'karya.yml')

    expect(configuration.backend_class).to eq(Karya::Backend::Postgres)
    expect(configuration.backend_options).to eq(url: 'postgres://localhost/test')
    expect(configuration.job_paths).to eq(['app/jobs', 'lib/jobs'])
    expect(configuration.boot_files).to eq(['config/boot/jobs.rb'])
  end

  it 'returns defaults when the config file is missing' do
    loader.load(path: 'missing.yml')

    expect(configuration.backend_class).to be_nil
    expect(configuration.job_paths).to eq(['app/jobs'])
    expect(configuration.boot_files).to eq([])
  end

  it 'allows a blank backend when backend_config is omitted' do
    File.write(File.join(root, 'karya.yml'), "defaults:\n  job_paths:\n    - app/jobs\n")

    loader.load(path: 'karya.yml')

    expect(configuration.backend_class).to be_nil
    expect(configuration.backend_options).to be_nil
    expect(configuration.job_paths).to eq(['app/jobs'])
  end

  it 'treats nil job_paths and boot_files as empty arrays' do
    File.write(
      File.join(root, 'karya.yml'),
      <<~YAML
        defaults:
          backend: sqlite
          backend_config:
            url: sqlite3:///tmp/test.sqlite3
          job_paths:
          boot_files:
      YAML
    )

    loader.load(path: 'karya.yml')

    expect(configuration.job_paths).to eq([])
    expect(configuration.boot_files).to eq([])
  end

  it 'rejects unknown config keys' do
    File.write(File.join(root, 'karya.yml'), "defaults:\n  backend: sqlite\n  extra: true\n")

    expect { loader.load(path: 'karya.yml') }.to raise_error(
      Karya::InvalidFrameworkConfigurationError,
      /unknown Karya config key/
    )
  end

  it 'rejects unsupported backend names' do
    File.write(File.join(root, 'karya.yml'), "defaults:\n  backend: bogus\n")

    expect { loader.load(path: 'karya.yml') }.to raise_error(
      Karya::InvalidFrameworkConfigurationError,
      /unsupported Karya backend/
    )
  end

  it 'rejects invalid job_paths and backend_config sections' do
    File.write(
      File.join(root, 'karya.yml'),
      <<~YAML
        defaults:
          backend: sqlite
          backend_config: invalid
          job_paths: app/jobs
      YAML
    )

    expect { loader.load(path: 'karya.yml') }.to raise_error(
      Karya::InvalidFrameworkConfigurationError,
      /backend_config/
    )
  end

  it 'rejects invalid boot_files sections' do
    File.write(
      File.join(root, 'karya.yml'),
      <<~YAML
        defaults:
          backend: sqlite
          backend_config:
            url: sqlite3:///tmp/test.sqlite3
          boot_files: config/boot/jobs.rb
      YAML
    )

    expect { loader.load(path: 'karya.yml') }.to raise_error(
      Karya::InvalidFrameworkConfigurationError,
      /boot_files/
    )
  end

  it 'rejects a blank backend when backend_config is present' do
    File.write(
      File.join(root, 'karya.yml'),
      <<~YAML
        defaults:
          backend:
          backend_config:
            url: postgres://localhost/test
      YAML
    )

    expect { loader.load(path: 'karya.yml') }.to raise_error(
      Karya::InvalidFrameworkConfigurationError,
      /backend cannot be blank/
    )
  end

  it 'rejects yaml files whose root is not a mapping' do
    File.write(File.join(root, 'karya.yml'), "- postgres\n")

    expect { loader.load(path: 'karya.yml') }.to raise_error(
      Karya::InvalidFrameworkConfigurationError,
      /root to be a mapping/
    )
  end

  it 'rejects malformed yaml' do
    File.write(File.join(root, 'karya.yml'), "defaults:\n  backend: [\n")

    expect { loader.load(path: 'karya.yml') }.to raise_error(
      Karya::InvalidFrameworkConfigurationError,
      /failed to parse Karya config YAML/
    )
  end

  it 'rejects erb evaluation errors' do
    File.write(File.join(root, 'karya.yml'), "<%= raise 'boom' %>\n")

    expect { loader.load(path: 'karya.yml') }.to raise_error(
      Karya::InvalidFrameworkConfigurationError,
      /failed to evaluate Karya config ERB/
    )
  end
end
