# frozen_string_literal: true

RSpec.describe 'Karya::CLI::EnvPrefix' do
  let(:env_prefix_class) { Karya::CLI.const_get(:EnvPrefix, false) }

  it 'normalizes mixed input into an uppercase env prefix' do
    expect(env_prefix_class.new(' karya workers ').normalize).to eq('KARYA_WORKERS')
  end

  it 'rejects prefixes with no alphanumeric content' do
    expect do
      env_prefix_class.new('___').normalize
    end.to raise_error(Karya::InvalidWorkerSupervisorConfigurationError, /Invalid value for --env-prefix/)
  end
end
