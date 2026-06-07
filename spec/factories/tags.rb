# frozen_string_literal: true

FactoryBot.define do
  factory :tag do
    move
    sequence(:name) { |n| "Tag #{n}" }
    applies_to { "item" }

    trait :box do
      applies_to { "box" }
    end

    trait :both do
      applies_to { "both" }
    end
  end
end
