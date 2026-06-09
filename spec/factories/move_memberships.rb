FactoryBot.define do
  factory :move_membership do
    move
    user
    role { "contributor" }

    trait :admin do
      role { "admin" }
    end

    trait :contributor do
      role { "contributor" }
    end

    trait :viewer do
      role { "viewer" }
    end
  end
end
