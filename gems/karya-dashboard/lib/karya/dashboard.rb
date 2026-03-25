# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'cgi'
require 'json'

require_relative 'dashboard/version'

module Karya
  # Accessors for the packaged dashboard frontend assets.
  module Dashboard
    ROOT = File.expand_path('../..', __dir__)
    DIST_PATH = File.expand_path('dist', ROOT)
    ASSET_MANIFEST_PATH = File.expand_path('asset-manifest.json', DIST_PATH)
    DEFAULT_TITLE = 'Karya Dashboard'
    DEFAULT_MOUNT_ID = 'karya-dashboard-root'

    # Raised when the asset manifest is missing, likely because the dashboard frontend has not been built.
    class AssetManifestMissingError < StandardError; end

    def self.dist_path
      DIST_PATH
    end

    def self.asset_manifest_path
      ASSET_MANIFEST_PATH
    end

    def self.asset_manifest
      JSON.parse(File.read(asset_manifest_path))
    rescue Errno::ENOENT
      raise AssetManifestMissingError,
            "Run yarn prepackage-build in #{ROOT} to generate #{asset_manifest_path}"
    rescue JSON::ParserError
      raise AssetManifestMissingError,
            "The dashboard asset manifest at #{asset_manifest_path} is invalid. " \
            "Run yarn prepackage-build in #{ROOT} to rebuild it."
    end

    def self.entrypoint(name = 'dashboard')
      asset_manifest.fetch('entrypoints').fetch(name.to_s)
    end

    def self.javascript_paths(name = 'dashboard')
      entrypoint(name).fetch('scripts')
    end

    def self.stylesheet_paths(name = 'dashboard')
      entrypoint(name).fetch('styles')
    end

    def self.mount_id(name = 'dashboard')
      entrypoint(name).fetch('mount_id', DEFAULT_MOUNT_ID)
    end

    def self.render_tags(name: 'dashboard', asset_prefix: nil)
      prefix = normalize_asset_prefix(asset_prefix)
      tags = stylesheet_paths(name).map do |stylesheet_path|
        %(<link rel="stylesheet" href="#{asset_url(stylesheet_path, prefix)}">)
      end
      javascript_paths(name).each do |script_path|
        tags << %(<script type="module" src="#{asset_url(script_path, prefix)}"></script>)
      end
      tags.join("\n")
    end

    def self.render_document(
      title: DEFAULT_TITLE,
      mount_path: '/karya',
      asset_prefix: nil,
      name: 'dashboard'
    )
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>#{escape_html(title)}</title>
            #{render_tags(name:, asset_prefix:)}
          </head>
          <body>
            <div id="#{escape_html(mount_id(name))}" data-karya-mount-path="#{escape_html(mount_path)}"></div>
          </body>
        </html>
      HTML
    end

    def self.asset_url(asset_path, asset_prefix)
      "#{asset_prefix}#{asset_path}"
    end

    def self.normalize_asset_prefix(asset_prefix)
      prefix = asset_prefix.to_s
      return '' if prefix.empty?

      normalized = prefix.gsub(%r{/+\z}, '')
      return normalized if prefix.match?(%r{\Ahttps?://}) || prefix.start_with?('//')
      return '' if normalized.empty?

      normalized = "/#{normalized}" unless normalized.start_with?('/')
      normalized
    end

    def self.escape_html(value)
      CGI.escapeHTML(value.to_s)
    end
  end
end
