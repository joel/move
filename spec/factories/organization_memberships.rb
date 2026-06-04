FactoryBot.define do
  factory :organization_membership do
    organization
    user
    role { "member" }

    trait :owner do
      role { "owner" }
    end
  end
end
