# frozen_string_literal: true

RSpec.describe 'Karya::Worker::MutableGraphCopy' do
  let(:mutable_graph_copy_class) { Karya::Worker.const_get(:MutableGraphCopy, false) }

  it 'duplicates nested hashes and arrays deeply' do
    original = { 'account' => { 'ids' => [1, '2'] } }

    duplicate = mutable_graph_copy_class.call(original)
    duplicate['account']['ids'] << 3

    expect(original).to eq({ 'account' => { 'ids' => [1, '2'] } })
  end

  it 'duplicates mutable scalar values like strings and times' do
    original_time = Time.utc(2026, 4, 23, 12, 0, 0)
    original_string = 'billing'

    duplicated_time = mutable_graph_copy_class.call(original_time)
    duplicated_string = mutable_graph_copy_class.call(original_string)

    expect(duplicated_time).to eq(original_time)
    expect(duplicated_time).not_to be(original_time)
    expect(duplicated_string).to eq(original_string)
    expect(duplicated_string).not_to be(original_string)
  end
end
