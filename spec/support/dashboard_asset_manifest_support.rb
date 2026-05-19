# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module DashboardAssetManifestSupport
  module_function

  def fixture_manifest_path
    File.expand_path('../../gems/karya-dashboard/spec/fixtures/asset-manifest.json', __dir__)
  end

  def preserve_cached_manifest
    manifest_defined = Karya::Dashboard.instance_variable_defined?(:@asset_manifest)
    manifest_path_defined = Karya::Dashboard.instance_variable_defined?(:@asset_manifest_path)
    cached_manifest = Karya::Dashboard.instance_variable_get(:@asset_manifest) if manifest_defined
    cached_manifest_path = Karya::Dashboard.instance_variable_get(:@asset_manifest_path) if manifest_path_defined
    original_asset_manifest_path_method = Karya::Dashboard.method(:asset_manifest_path)
    yield
  ensure
    if manifest_defined
      Karya::Dashboard.instance_variable_set(:@asset_manifest, cached_manifest)
    else
      Karya::Dashboard.remove_instance_variable(:@asset_manifest) if Karya::Dashboard.instance_variable_defined?(:@asset_manifest)
    end

    if manifest_path_defined
      Karya::Dashboard.instance_variable_set(:@asset_manifest_path, cached_manifest_path)
    else
      Karya::Dashboard.remove_instance_variable(:@asset_manifest_path) if Karya::Dashboard.instance_variable_defined?(:@asset_manifest_path)
    end

    Karya::Dashboard.define_singleton_method(:asset_manifest_path) do
      original_asset_manifest_path_method.call
    end
  end
end

RSpec.configure do |config|
  config.around(:each, :dashboard_manifest_fixture) do |example|
    DashboardAssetManifestSupport.preserve_cached_manifest do
      fixture_manifest_path = DashboardAssetManifestSupport.fixture_manifest_path
      Karya::Dashboard.define_singleton_method(:asset_manifest_path) { fixture_manifest_path }
      Karya::Dashboard.reload_asset_manifest!(fixture_manifest_path)
      example.run
    end
  end
end
