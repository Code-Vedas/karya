# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
version = File.read(File.expand_path('lib/karya/sinatra/version.rb', __dir__))
              .match(/VERSION\s*=\s*['"]([^'"]+)['"]/)[1]

Gem::Specification.new do |spec|
  spec.name = 'karya-sinatra'
  spec.version = version
  spec.authors = ['Nitesh Purohit', 'Codevedas Inc.']
  spec.email = ['nitesh.purohit.it@gmail.com', 'team@codevedas.com']
  spec.summary = 'Sinatra integration for Karya with Sequel support.'
  spec.description = <<~DESC
    Karya-Sinatra provides the Sinatra-facing integration layer for Karya. It
    composes the core Karya runtime, the Sequel adapter package, and the
    dashboard addon for Sinatra hosts.
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
  spec.metadata['rubygems_uri'] = 'https://rubygems.org/gems/karya-sinatra'
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir['{bin,lib}/**/*', 'LICENSE', 'Rakefile', 'README.md']
  end
  spec.require_paths = ['lib']
  spec.add_dependency 'karya', "= #{version}"
  spec.add_dependency 'karya-dashboard', "= #{version}"
  spec.add_dependency 'karya-sequel', "= #{version}"
  spec.add_dependency 'rack', '>= 2.2'
  spec.add_dependency 'sinatra', '>= 3.0', '< 5.0'
  spec.required_ruby_version = '>= 3.2'
end
