# frozen_string_literal: true

FactoryBot.define do
  factory :item do
    move
    box { association :box, move: move }
    name { "Coffee Maker" }
    quantity { 1 }
    created_via { "recognition" }
    review_state { "pending_review" }
    presence_state { "in_box" }

    trait :auto_confirmed do
      review_state { "auto_confirmed" }
      confidence_score { 0.95 }
    end

    trait :confirmed do
      review_state { "confirmed" }
    end

    trait :manual do
      created_via { "manual" }
      review_state { "confirmed" }
    end
  end
end
