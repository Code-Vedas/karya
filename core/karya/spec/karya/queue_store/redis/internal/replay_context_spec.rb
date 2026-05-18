# frozen_string_literal: true

RSpec.describe Karya::QueueStore::Redis.const_get(:Internal, false)::ReplayContext do
  subject(:context) { described_class.new }

  it 'marks replay state only for the current thread' do
    other_thread_state = Queue.new

    context.with_replay(reservation_token_base: 'reservation-token') do
      other_thread = Thread.new do
        other_thread_state << [context.replaying?, context.bypass?, context.token_base]
      end
      other_thread.join

      expect(context.replaying?).to be(true)
      expect(context.bypass?).to be(true)
      expect(context.token_base).to eq('reservation-token')
    end

    expect(other_thread_state.pop).to eq([false, false, nil])
    expect(context.replaying?).to be(false)
    expect(context.bypass?).to be(false)
    expect(context.token_base).to be_nil
  end
end
