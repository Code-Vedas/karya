# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::Dashboard do
  let(:fixture_manifest_path) { File.expand_path('../fixtures/asset-manifest.json', __dir__) }

  describe 'packaging metadata' do
    it 'has a version number' do
      expect(described_class::VERSION).to eq('0.1.0')
    end

    it 'exposes the packaged dashboard paths' do
      expect(described_class.dist_path).to end_with('/gems/karya-dashboard/dist')
      expect(described_class.asset_manifest_path).to end_with(
        '/gems/karya-dashboard/dist/asset-manifest.json'
      )
    end

    it 'loads the dashboard entrypoint from the asset manifest' do
      allow(described_class).to receive(:asset_manifest_path).and_return(fixture_manifest_path)

      entrypoint = described_class.entrypoint

      expect(entrypoint.fetch('html')).to eq('/index.html')
      expect(entrypoint.fetch('mount_id')).to eq('karya-dashboard-root')
      expect(described_class.javascript_paths).to contain_exactly(
        '/assets/dashboard-runtime.js',
        '/assets/dashboard-abc123.js'
      )
      expect(described_class.stylesheet_paths).to all(start_with('/assets/'))
    end

    it 'returns the cached manifest when it becomes available during synchronized reload' do
      allow(described_class).to receive(:asset_manifest_path).and_return(fixture_manifest_path)

      cached_manifest = { 'entrypoints' => {} }.freeze
      lookup_count = 0

      allow(described_class).to receive(:cached_asset_manifest) do |_current_manifest_path|
        lookup_count += 1
        lookup_count == 1 ? nil : cached_manifest
      end
      allow(described_class).to receive(:reload_asset_manifest!)

      expect(described_class.asset_manifest).to eq(cached_manifest)
      expect(described_class).not_to have_received(:reload_asset_manifest!)
    end
  end

  describe 'HTML helpers' do
    it 'renders tags for the packaged assets' do
      allow(described_class).to receive(:asset_manifest_path).and_return(fixture_manifest_path)

      tags = described_class.render_tags

      expect(tags).to include('<link rel="stylesheet" href="/assets/')
      expect(tags.scan('<script type="module"').size).to eq(2)
      expect(tags).to include('src="/assets/dashboard-runtime.js"')
      expect(tags).to include('<script type="module" src="/assets/')
    end

    it 'renders dashboard documents with optional asset prefixes' do
      allow(described_class).to receive(:asset_manifest_path).and_return(fixture_manifest_path)

      document = described_class.render_document(
        title: 'Fixture Host',
        mount_path: '/ops/karya',
        asset_prefix: '/dashboard'
      )

      expect(document).to include('<title>Fixture Host</title>')
      expect(document).to include('id="karya-dashboard-root"')
      expect(document).to include('data-karya-mount-path="/ops/karya"')
      expect(document).to include('href="/dashboard/assets/')
      expect(document).to include('src="/dashboard/assets/')
    end

    it 'escapes interpolated HTML values in rendered documents' do
      allow(described_class).to receive(:asset_manifest_path).and_return(fixture_manifest_path)

      document = described_class.render_document(
        title: 'Ops <Dashboard>',
        mount_path: %(/ops/"karya"&more)
      )

      expect(document).to include('<title>Ops &lt;Dashboard&gt;</title>')
      expect(document).to include('data-karya-mount-path="/ops/&quot;karya&quot;&amp;more"')
      expect(document).not_to include('<title>Ops <Dashboard></title>')
    end

    it 'normalizes trailing slashes in asset prefixes' do
      allow(described_class).to receive(:asset_manifest_path).and_return(fixture_manifest_path)

      tags = described_class.render_tags(asset_prefix: '/dashboard/')

      expect(tags).to include('href="/dashboard/assets/')
      expect(tags).to include('src="/dashboard/assets/')
      expect(tags).not_to include('/dashboard//assets/')
    end

    it 'normalizes repeated trailing slashes in asset prefixes' do
      allow(described_class).to receive(:asset_manifest_path).and_return(fixture_manifest_path)

      tags = described_class.render_tags(asset_prefix: '/dashboard///')

      expect(tags).to include('href="/dashboard/assets/')
      expect(tags).to include('src="/dashboard/assets/')
      expect(tags).not_to include('/dashboard//assets/')
    end

    it 'treats slash-only asset prefixes as the root path' do
      allow(described_class).to receive(:asset_manifest_path).and_return(fixture_manifest_path)

      tags = described_class.render_tags(asset_prefix: '/')

      expect(tags).to include('href="/assets/')
      expect(tags).to include('src="/assets/')
      expect(tags).not_to include('//assets/')
    end

    it 'preserves protocol-relative asset prefixes' do
      allow(described_class).to receive(:asset_manifest_path).and_return(fixture_manifest_path)

      tags = described_class.render_tags(asset_prefix: '//cdn.example.com/dashboard///')

      expect(tags).to include('href="//cdn.example.com/dashboard/assets/')
      expect(tags).to include('src="//cdn.example.com/dashboard/assets/')
    end

    it 'normalizes relative asset prefixes to absolute paths' do
      allow(described_class).to receive(:asset_manifest_path).and_return(fixture_manifest_path)

      tags = described_class.render_tags(asset_prefix: 'dashboard')

      expect(tags).to include('href="/dashboard/assets/')
      expect(tags).to include('src="/dashboard/assets/')
    end

    it 'preserves absolute asset prefixes' do
      allow(described_class).to receive(:asset_manifest_path).and_return(fixture_manifest_path)

      tags = described_class.render_tags(asset_prefix: 'https://cdn.example.com/dashboard/')

      expect(tags).to include('href="https://cdn.example.com/dashboard/assets/')
      expect(tags).to include('src="https://cdn.example.com/dashboard/assets/')
    end
  end

  describe 'error handling' do
    it 'raises a useful error when the asset manifest is missing' do
      allow(described_class).to receive(:asset_manifest_path).and_return('/tmp/does-not-exist.json')

      expect { described_class.asset_manifest }.to raise_error(
        Karya::Dashboard::AssetManifestMissingError,
        /Run corepack yarn prepackage-build/
      )
    end

    it 'raises a useful error when the asset manifest is invalid JSON' do
      Dir.mktmpdir('karya-dashboard-manifest') do |tmp_dir|
        invalid_manifest = File.join(tmp_dir, 'asset-manifest.json')
        File.write(invalid_manifest, '{invalid json')
        allow(described_class).to receive(:asset_manifest_path).and_return(invalid_manifest)

        expect { described_class.asset_manifest }.to raise_error(
          Karya::Dashboard::AssetManifestInvalidError,
          /asset manifest .* is invalid/i
        )
      end
    end
  end
end
