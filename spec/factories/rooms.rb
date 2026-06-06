# frozen_string_literal: true

FactoryBot.define do
  factory :room do
    move
    sequence(:name) { |n| "Room #{n}" }
  end
end
