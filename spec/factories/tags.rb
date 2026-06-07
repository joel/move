# frozen_string_literal: true

FactoryBot.define do
  factory :tag do
    move
    sequence(:name) { |n| "Tag #{n}" }
  end
end
