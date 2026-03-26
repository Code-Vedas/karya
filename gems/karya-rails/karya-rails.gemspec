# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
version = File.read(File.expand_path('lib/karya/rails/version.rb', __dir__))
              .match(/VERSION\s*=\s*['"]([^'"]+)['"]/)[1]

Gem::Specification.new do |spec|
  spec.name = 'karya-rails'
  spec.version = version
  spec.authors = ['Nitesh Purohit', 'Codevedas Inc.']
  spec.email = ['nitesh.purohit.it@gmail.com', 'team@codevedas.com']
  spec.summary = 'Rails integration for Karya with Active Record support.'
  spec.description = <<~DESC
    Karya-Rails provides the Rails integration surface for Karya. It composes
    the core Karya runtime, the Active Record adapter package, and the
    dashboard addon for Rails hosts.
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
  spec.metadata['rubygems_uri'] = 'https://rubygems.org/gems/karya-rails'
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir['{app,bin,config,lib}/**/*', 'LICENSE', 'Rakefile', 'README.md']
  end
  spec.require_paths = ['lib']
  spec.add_dependency 'karya', "= #{version}"
  spec.add_dependency 'karya-activerecord', "= #{version}"
  spec.add_dependency 'karya-dashboard', "= #{version}"
  spec.add_dependency 'rails', '>= 7.1', '< 9.0'
  spec.required_ruby_version = '>= 3.2'
end
