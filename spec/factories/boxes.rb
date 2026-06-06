# frozen_string_literal: true

FactoryBot.define do
  factory :box do
    move
    sequence(:number, &:to_s)
    sequence(:qr_token) { |n| "qr-#{n}-#{SecureRandom.hex(4)}" }
    status { "packing" }

    trait :sealed do
      status { "sealed" }
    end

    trait :with_dimensions do
      length_cm { 40 }
      width_cm { 30 }
      height_cm { 25 }
      weight_kg { 8 }
    end

    trait :with_room do
      room
    end
  end
end
