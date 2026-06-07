# frozen_string_literal: true

FactoryBot.define do
  factory :item_tag do
    item
    tag { association :tag, move: item.move }
  end
end
