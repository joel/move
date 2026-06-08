# frozen_string_literal: true

FactoryBot.define do
  factory :item_search_document do
    item
    move { item.move }
    search_text { "Coffee maker kitchen" }

    # A deterministic unit-length-ish embedding for semantic specs.
    trait :embedded do
      embedding { Array.new(1536) { 0.01 } }
      embedding_model { "fake-1" }
      embedded_at { Time.current }
    end
  end
end
