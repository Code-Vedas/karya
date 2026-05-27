# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'erb'
require 'yaml'

module Karya
  module Internal
    module Config
      # Loads framework-facing static Karya configuration from config/karya.yml.
      class FileLoader
        BACKEND_CLASS_NAMES = {
          'in_memory' => 'Karya::Backend::InMemory',
          'sqlite' => 'Karya::Backend::SQLite',
          'postgres' => 'Karya::Backend::Postgres',
          'mysql' => 'Karya::Backend::MySQL',
          'redis' => 'Karya::Backend::Redis'
        }.freeze
        ALLOWED_KEYS = %w[backend backend_config job_paths boot_files].freeze

        def initialize(configuration:, runtime_context:)
          @configuration = configuration
          @runtime_context = runtime_context
        end

        def load(path: 'config/karya.yml')
          absolute_path = runtime_context.resolve_path(path)
          payload = File.exist?(absolute_path) ? parse_yaml(absolute_path) : {}
          apply_configuration(merge_environment_config(payload))
          configuration
        end

        private

        attr_reader :configuration, :runtime_context

        def parse_yaml(path)
          rendered = ERB.new(File.read(path), trim_mode: '-').result
          parsed = YAML.safe_load(rendered, aliases: true) || {}
          raise InvalidFrameworkConfigurationError, "expected Karya config YAML root to be a mapping in #{path}" unless parsed.is_a?(Hash)

          stringify_keys(parsed)
        rescue Psych::Exception => e
          raise_config_error(prefix: 'failed to parse Karya config YAML', path:, error: e)
        rescue StandardError, SyntaxError => e
          raise_config_error(prefix: 'failed to evaluate Karya config ERB', path:, error: e)
        end

        def merge_environment_config(payload)
          environment_name = runtime_context.environment_name
          defaults = hash_section(payload['defaults'], section_name: 'defaults')
          environment = hash_section(payload[environment_name], section_name: environment_name)
          deep_merge(defaults, environment)
        end

        def apply_configuration(config)
          validate_known_keys(config)
          apply_backend_configuration(config)
          apply_path_configuration(config)
        end

        def resolve_backend_class(backend_name)
          normalized_backend_name = backend_name.to_s.strip
          resolved_backend_class_name = BACKEND_CLASS_NAMES.fetch(normalized_backend_name) do
            raise InvalidFrameworkConfigurationError,
                  "unsupported Karya backend #{backend_name.inspect}; expected one of #{BACKEND_CLASS_NAMES.keys.join(', ')}"
          end

          Karya::ConstantResolver.new(resolved_backend_class_name).resolve
        end

        def hash_section(value, section_name:)
          return {} if value.nil?
          raise InvalidFrameworkConfigurationError, "Karya config section #{section_name.inspect} must be a mapping" unless value.is_a?(Hash)

          stringify_keys(duplicate_value(value))
        end

        def array_section(value, section_name:)
          return [] if value.nil?
          raise InvalidFrameworkConfigurationError, "Karya config section #{section_name.inspect} must be an array" unless value.is_a?(Array)

          duplicate_value(value)
        end

        def deep_merge(left, right)
          left.merge(right) do |_key, old_value, new_value|
            old_value.is_a?(Hash) && new_value.is_a?(Hash) ? deep_merge(old_value, new_value) : new_value
          end
        end

        def validate_known_keys(config)
          unknown_keys = config.keys - ALLOWED_KEYS
          return if unknown_keys.empty?

          raise InvalidFrameworkConfigurationError,
                "unknown Karya config key(s): #{unknown_keys.map(&:inspect).join(', ')}"
        end

        def apply_backend_configuration(config)
          backend_name = config.fetch('backend', nil)
          backend_config = hash_section(config['backend_config'], section_name: 'backend_config')
          return apply_blank_backend_configuration(backend_config) if blank_backend_name?(backend_name)

          configuration.backend(resolve_backend_class(backend_name), **symbolize_keys(backend_config))
        end

        def apply_blank_backend_configuration(backend_config)
          return if backend_config.empty?

          raise InvalidFrameworkConfigurationError, 'Karya config backend cannot be blank'
        end

        def blank_backend_name?(backend_name)
          backend_name.nil? || backend_name.to_s.strip.empty?
        end

        def apply_path_configuration(config)
          apply_path_option(config, key: 'job_paths') { |paths| configuration.job_paths = paths }
          apply_path_option(config, key: 'boot_files') { |paths| configuration.boot_files = paths }
        end

        def apply_path_option(config, key:)
          return unless config.key?(key)

          yield array_section(config[key], section_name: key)
        end

        def duplicate_value(value)
          transform_value(value) { |item| item }
        end

        def stringify_keys(value)
          transform_value(value, &:to_s)
        end

        def symbolize_keys(value)
          transform_value(value, &:to_sym)
        end

        def transform_value(value, &key_transform)
          case value
          when Hash
            value.each_with_object({}) do |(key, item), duplicate|
              duplicate[yield(key)] = transform_value(item, &key_transform)
            end
          when Array
            value.map { |item| transform_value(item, &key_transform) }
          else
            value
          end
        end

        def raise_config_error(prefix:, path:, error:)
          message = error.message
          raise InvalidFrameworkConfigurationError, "#{prefix} at #{path}: #{message}"
        end
      end
    end
  end
end
