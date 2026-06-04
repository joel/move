# frozen_string_literal: true

FactoryBot.define do
  factory :organization_membership do
    organization
    user

    trait :account_admin do
      account_admin { true }
    end
  end
end
