# frozen_string_literal: true

FactoryBot.define do
  factory :find_list_entry do
    move
    user
    item { association :item, move: move }
  end
end
