FactoryBot.define do
  sequence(:organization_slug) { |n| "org-#{n}" }

  factory :organization do
    name { "Acme Movers" }
    slug { generate(:organization_slug) }
  end
end
