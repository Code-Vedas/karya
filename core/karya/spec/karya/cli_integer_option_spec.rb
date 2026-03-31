# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Karya::CLI do
  let(:integer_option_class) { described_class.const_get(:IntegerOption, false) }

  describe 'IntegerOption' do
    it 'normalizes string and whole-float integer options' do
      expect(integer_option_class.new(:processes, '3').normalize).to eq(3)
      expect(integer_option_class.new(:threads, 3.0).normalize).to eq(3)
    end

    it 'rejects malformed integer options' do
      expect do
        integer_option_class.new(:processes, 'oops').normalize
      end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /Invalid value for --processes/)
    end
  end
end
