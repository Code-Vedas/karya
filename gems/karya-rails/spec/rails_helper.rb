# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

ENV['RAILS_ENV'] ||= 'test'
require_relative 'dummy/config/environment'

abort('The Rails environment is running in production mode!') if Rails.env.production?

require 'rspec/rails'

RSpec.configure(&:filter_rails_from_backtrace!)
