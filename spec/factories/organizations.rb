# frozen_string_literal: true

FactoryBot.define do
  sequence(:organization_slug) { |n| "org#{n}" }

  factory :organization do
    name { "Acme Relocation" }
    slug { generate(:organization_slug) }
    created_by_user factory: %i[user]
  end
end
