# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'json'

module Karya
  module Hanami
    module CLI
      # Framework-native Hanami runtime control command.
      class Runtime < ::Hanami::CLI::Commands::App::Command
        desc 'Inspect or control a Karya worker runtime for the given comma-separated queues'

        argument :action, required: true, desc: 'inspect, drain, or force-stop'
        argument :queues, required: true, desc: 'Comma-separated queue names'
        option :name, required: false, desc: 'Logical worker name used for runtime control'

        def call(action:, queues:, **options)
          framework.load_config_file!
          resolved_action = action.to_s.tr('-', '_')
          normalized_queues = Karya::Internal::FrameworkRuntimeIdentity.parse_queues(queues)
          worker_name = options[:name]
          payload = case resolved_action
                    when 'inspect' then framework.runtime_inspect(queues: normalized_queues, name: worker_name)
                    when 'drain' then framework.runtime_drain(queues: normalized_queues, name: worker_name)
                    when 'force_stop' then framework.runtime_force_stop(queues: normalized_queues, name: worker_name)
                    else
                      raise ArgumentError, "unsupported runtime action #{action.inspect}"
                    end
          puts JSON.pretty_generate(payload) if payload.is_a?(Hash)
        end

        private

        def framework
          Karya::Hanami
        end
      end
    end
  end
end
