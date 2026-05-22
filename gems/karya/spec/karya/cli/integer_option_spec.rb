# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::CLI::IntegerOption' do
  let(:integer_option_class) { Karya::CLI.const_get(:IntegerOption, false) }

  it 'normalizes integer-like values' do
    expect(integer_option_class.new(:threads, '3').normalize).to eq(3)
    expect(integer_option_class.new(:threads, 3.0).normalize).to eq(3)
  end

  it 'rejects non-positive values' do
    expect do
      integer_option_class.new(:threads, 0).normalize
    end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /Expected a positive integer/)
  end
end
