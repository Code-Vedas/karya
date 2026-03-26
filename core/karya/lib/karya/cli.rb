# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'thor'

module Karya
  # The CLI class defines the command-line interface for the Karya gem. It uses Thor to handle command parsing and execution.
  class CLI < Thor
    package_name 'karya'
    default_task :help

    def self.start(given_args = ARGV, config = {})
      puts header
      super
    end

    def self.header
      art = <<~'TEXT'
         _  __     _     ____   __   __    _
        | |/ /    / \   |  _ \  \ \ / /   / \
        | ' /    / _ \  | |_) |  \ V /   / _ \
        | . \   / ___ \ |  _ <    | |   / ___ \
        |_|\_\ /_/   \_\|_| \_\   |_|  /_/   \_\
      TEXT

      "#{art}\n#{Karya::TAGLINE} · v#{Karya::VERSION}\n"
    end

    map %w[--help -h] => :help
    map %w[--version -v] => :version

    desc 'version', 'Print the current version'
    def version
      # version is printed in the header, so we can just exit here
      exit(0)
    end

    desc 'help [COMMAND]', 'Describe available commands or one specific command'
    def help(command = nil)
      super
    end
  end
end
