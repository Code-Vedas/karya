# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'rails/command'
require 'rails/command/environment_argument'
require 'json'
require 'karya/rails'

module Rails
  module Command
    module Karya
      # Rails runtime inspection and control commands for Karya workers.
      class RuntimeCommand < Base
        include EnvironmentArgument

        class_option :name, type: :string, desc: 'Logical worker name used for runtime control'

        desc 'inspect QUEUE [QUEUE ...]', 'Inspect the worker runtime for the given queues'
        def inspect(*queues)
          boot_application_for(queues)
          say JSON.pretty_generate(::Karya::Rails.runtime_inspect(queues:, name: options[:name]))
        end

        desc 'drain QUEUE [QUEUE ...]', 'Request graceful drain for the worker runtime'
        def drain(*queues)
          boot_application_for(queues)
          ::Karya::Rails.runtime_drain(queues:, name: options[:name])
        end

        desc 'force_stop QUEUE [QUEUE ...]', 'Force-stop the worker runtime'
        map 'force-stop' => :force_stop
        def force_stop(*queues)
          boot_application_for(queues)
          ::Karya::Rails.runtime_force_stop(queues:, name: options[:name])
        end

        def boot_application_for(queues)
          raise Error, 'at least one queue is required' if queues.empty?

          boot_application!
        end
        private :boot_application_for
      end
    end
  end
end
