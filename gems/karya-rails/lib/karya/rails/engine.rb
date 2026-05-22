# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Karya
  module Rails
    # Engine class is responsible for isolating the Karya::Rails namespace and integrating it with the Rails application.
    class Engine < ::Rails::Engine
      isolate_namespace Karya::Rails

      initializer 'karya.load_config_file' do
        Karya::Rails.load_config_file!
      end

      rake_tasks do
        load File.expand_path('../../tasks/karya_rails_tasks.rake', __dir__)
      end
    end
  end
end
