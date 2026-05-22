# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::CLI do
  describe 'private helpers' do
    it 'accepts nil for optional integer options before coercion' do
      cli = described_class.new
      allow(cli).to receive(:options).and_return({ max_iterations: nil })

      expect(cli.send(:coerce_optional_positive_integer_option, :max_iterations)).to be_nil
    end
  end
end
