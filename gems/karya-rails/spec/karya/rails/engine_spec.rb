# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../../rails_helper'

RSpec.describe Karya::Rails::Engine do
  it 'loads the packaged rake tasks' do
    expect { described_class.load_tasks }.not_to raise_error
  end
end
