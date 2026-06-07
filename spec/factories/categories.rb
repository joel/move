# frozen_string_literal: true

FactoryBot.define do
  factory :category do
    move
    sequence(:name) { |n| "Category #{n}" }
  end
end
