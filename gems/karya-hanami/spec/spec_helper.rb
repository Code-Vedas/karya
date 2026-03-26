# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
unless ENV['NO_COVERAGE'] == '1'
  require 'simplecov'

  SimpleCov.start do
    enable_coverage :branch
    track_files 'lib/**/*.rb'
    add_filter '/spec/'
    minimum_coverage line: 100, branch: 100
  end
end

require 'karya/hanami'

Dir[File.expand_path('support/**/*.rb', __dir__)].each { |file| require file }
Dir[File.expand_path('e2e/support/**/*.rb', __dir__)].each { |file| require file }
Dir[File.expand_path('../../../spec/support/**/*.rb', __dir__)].each { |file| require file }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
