# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
version = File.read(File.expand_path('lib/karya/activerecord/version.rb', __dir__))
              .match(/VERSION\s*=\s*['"]([^'"]+)['"]/)[1]

Gem::Specification.new do |spec|
  spec.name = 'karya-activerecord'
  spec.version = version
  spec.authors = ['Nitesh Purohit', 'Codevedas Inc.']
  spec.email = ['nitesh.purohit.it@gmail.com', 'team@codevedas.com']
  spec.summary = 'Active Record adapter support for Karya.'
  spec.description = <<~DESC
    Karya-ActiveRecord provides the Active Record adapter surface for Karya,
    including adapter key selection and connection-strategy helpers for SQL
    deployments built on Active Record.
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
  spec.metadata['rubygems_uri'] = 'https://rubygems.org/gems/karya-activerecord'
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir['{bin,lib}/**/*', 'LICENSE', 'Rakefile', 'README.md']
  end
  spec.require_paths = ['lib']
  spec.add_dependency 'activerecord', '>= 7.1', '< 9.0'
  spec.add_dependency 'karya', "= #{version}"
  spec.required_ruby_version = '>= 3.2'
end
