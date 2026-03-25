# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
version = File.read(File.expand_path('lib/karya/dashboard/version.rb', __dir__))
              .match(/VERSION\s*=\s*['"]([^'"]+)['"]/)[1]

Gem::Specification.new do |spec|
  spec.name = 'karya-dashboard'
  spec.version = version
  spec.authors = ['Nitesh Purohit', 'Codevedas Inc.']
  spec.email = ['nitesh.purohit.it@gmail.com', 'team@codevedas.com']
  spec.summary = 'Packaged dashboard frontend for Karya hosts.'
  spec.description = <<~DESC
    Karya-Dashboard packages the React, TypeScript, SCSS, and Vite-built
    dashboard assets together with a Ruby wrapper that exposes the asset
    manifest and HTML rendering contract used by Karya host integrations.
  DESC
  spec.homepage = 'https://github.com/Code-Vedas/karya'
  spec.license = 'MIT'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/Code-Vedas/karya/issues'
  spec.metadata['changelog_uri'] = 'https://github.com/Code-Vedas/karya/blob/main/CHANGELOG.md'
  spec.metadata['documentation_uri'] = 'https://github.com/Code-Vedas/karya/tree/main/docs'
  spec.metadata['homepage_uri'] = 'https://github.com/Code-Vedas/karya'
  spec.metadata['source_code_uri'] = 'https://github.com/Code-Vedas/karya.git'
  spec.metadata['funding_uri'] = 'https://github.com/sponsors/Code-Vedas'
  spec.metadata['support_uri'] = 'https://github.com/Code-Vedas/karya/issues'
  spec.metadata['rubygems_uri'] = 'https://rubygems.org/gems/karya-dashboard'
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir['{bin,dist,lib}/**/*', 'LICENSE', 'Rakefile', 'README.md']
  end
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 3.2'
end
